# Keyboard Hit Counter 设计文档

**状态：** 已确认设计，待实现

**日期：** 2026-08-18

## 1. 目标

一个常驻 macOS 菜单栏的小工具：实时记录每个前台应用收到的键盘敲击次数，按天累计并本地持久化，同时保证对系统输入**零阻塞**。

## 2. 需求

### 2.1 功能需求

- **F1 形态**：菜单栏小应用（menulet），点击菜单栏图标弹出计数列表，无 Dock 图标、无主窗口。
- **F2 计数口径**：每个 `keyDown` 事件计 1 次。包含修饰键、功能键、长按产生的自动重复事件。
- **F3 排除自身**：本应用自己产生的按键不计入任何应用。
- **F4 持久化**：按「日期 → 各应用计数」本地持久化，同一天内跨应用重启累计。
- **F5 列表展示**：按「今日计数」降序，每行显示应用图标、显示名、今日计数、累计计数。

### 2.2 非功能需求（硬性约束）

- **P1 零阻塞**：按键事件完全不等待任何记录逻辑完成。使用 `CGEventTapOptions.listenOnly`，系统不等待回调、不修改事件。
- **P2 热路径亚微秒**：keydown 回调内只做「一次原子读 + 一次原子递增」，无锁、无分配、无 I/O、无 syscall、无字符串处理。
- **P3 异步解耦**：持久化、聚合、UI 刷新全部在后台，永不进入热路径。
- **P4 最低系统**：macOS 13（Ventura）。
- **P5 零第三方依赖**：仅用系统框架与 Swift 标准库。

## 3. 技术栈

- 语言：Swift 6 工具链（Swift 5 语言模式，规避与 C 互操作、AppKit 回调的严格并发摩擦）。
- UI：SwiftUI + AppKit（`NSStatusItem` + `NSPopover` + `NSHostingView`）。
- 事件：Quartz `CGEventTap`（`listenOnly` + `.headInsertEventTap`）。
- 前台应用：`NSWorkspace`。
- 构建：SwiftPM（C 目标 + 核心库目标 + 可执行目标 + 测试目标），`Makefile` 打包为 `.app`。
- 无第三方依赖，锁无关计数用 C11 `_Atomic int64_t`，经不透明 C 结构体暴露给 Swift（规避 Swift 对 `_Atomic` 类型的互操作问题）。

## 4. 架构与模块

> **目标布局**：模块 4.1–4.7 位于 `KeyboardHitCounterCore` 库目标（可被测试目标 `import`）；模块 4.8–4.10 位于 `KeyboardHitCounter` 可执行目标（SwiftPM 测试目标无法导入可执行目标，故拆分）。

```
┌──────────────────────────────────────────────────────────┐
│ 热路径（专用高优先级线程，唯一接触按键事件的地方）          │
│   KeyEventTap ──keydown──► CounterStore.incrementCurrentSlot()│
│                              （原子读 slot + 原子递增）    │
└──────────────────────────────────────────────────────────┘
                              │（异步，与事件流无关）
┌─────────────────────────────▼────────────────────────────┐
│ 温路径（后台）  FrontmostAppTracker ──► AppSlotRegistry    │
│                （NSWorkspace 通知，维护 bundleID↔slot）    │
└──────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────┐
│ 冷路径（后台队列 / 定时器）                                │
│   Aggregator（1s 聚合）──► StatusViewModel ──► UI         │
│   PersistenceWorker（固定 5s 周期 + 退出时 flush）          │
└──────────────────────────────────────────────────────────┘
```

### 4.1 `CAtomic`（C 目标）

`Sources/CAtomic/atomic_counter.h` 与 `atomic_counter.c`：基于 C11 `_Atomic int64_t` 的锁无关原语。对外用**不透明结构体** `khc_counters_t` 封装（C 侧持有 `_Atomic` 计数器数组 + 原子 `current_slot`），规避 Swift 对 `_Atomic` 类型的互操作问题；内存由 C 侧分配/释放。

```c
typedef struct khc_counters khc_counters_t;

khc_counters_t *khc_counters_create(int64_t capacity);          // 分配 capacity 个计数器，全零
void khc_counters_destroy(khc_counters_t *c);

int64_t khc_counters_increment_current(khc_counters_t *c);      // 热路径：counter[current_slot] 原子 +1
int64_t khc_counters_load(const khc_counters_t *c, int64_t slot);
void    khc_counters_set_current_slot(khc_counters_t *c, int64_t slot);
int64_t khc_counters_current_slot(const khc_counters_t *c);
int64_t khc_counters_capacity(const khc_counters_t *c);
```

### 4.2 `CounterStore`（锁无关计数）

`Sources/KeyboardHitCounterCore/CounterStore.swift`

- 持有连续内存的 slot 计数器数组，以及一个原子 `currentSlot`。
- **容量固定**：`maxSlots = 512` 的 `_Atomic int64_t` 数组在**启动时一次性分配，运行期永不扩容、永不移动内存**。这是热路径无锁读的安全前提——一旦运行期扩容会移动内存，热路径读旧指针即 use-after-free，因此禁止运行期扩容。
- **slot 0 为「忽略/未知」**：当最前台应用未知、是本应用自身、或槽位已满时，`currentSlot` 指向 0，其计数永不映射到任何 bundleID。热路径因此无分支。
- 对外接口：

```swift
final class CounterStore {
    static let maxSlots = 512

    func incrementCurrentSlot()              // 热路径：计数器[currentSlot] 原子 +1
    func setCurrentSlot(_ slot: Int)         // 原子写（slot ∈ [0, maxSlots)）
    func countsBySlot() -> [Int64]           // 后台：原子读全部 slot
}
```

### 4.3 `AppSlotRegistry`（bundleID ↔ slot 映射）

`Sources/KeyboardHitCounterCore/AppSlotRegistry.swift`

- 运行时内存映射，`os_unfair_lock` 保护。**不在热路径访问**；温路径（应用切换时分配 slot）与冷路径（聚合时反查 bundleID）均低频、经同一把锁访问。
- 槽位分配在 `[1, CounterStore.maxSlots)` 内单调递增、运行期不复用；分配满后返回 0（忽略）。槽位永不释放，因此 slot 与计数器的对应关系稳定。
- 对外接口：

```swift
final class AppSlotRegistry {
    func slot(forBundleID: String) -> Int      // 已存在返回旧 slot，否则分配新 slot；已满返回 0
    func bundleID(forSlot: Int) -> String?     // slot 0 返回 nil
}
```

### 4.4 `FrontmostAppTracker`（前台应用追踪）

`Sources/KeyboardHitCounterCore/FrontmostAppTracker.swift`

- 订阅 `NSWorkspace.didActivateApplicationNotification`，解析 bundleID，走 `AppSlotRegistry` 得到 slot，再 `CounterStore.setCurrentSlot`。
- 当前台是自身（`Bundle.main.bundleIdentifier`）或 bundleID 缺失时，slot 置 0。
- 每遇到一个「新出现的 bundleID」，从 `NSRunningApplication` 读取 `localizedName`，并把 `icon` 转成 PNG `Data`，写入 `AppMetadataStore`（`Data` 线程安全，`NSImage` 跨线程不安全）。
- 额外提供每 1 秒的低频兜底刷新，防止个别场景漏掉通知。

```swift
final class FrontmostAppTracker {
    func start(registry: AppSlotRegistry,
               counters: CounterStore,
               metadataStore: AppMetadataStore)
    func stop()
}
```

### 4.4.1 `AppMetadataStore`（应用显示名/图标缓存）

`Sources/KeyboardHitCounterCore/AppMetadataStore.swift`

- 线程安全的 `bundleID → 显示信息` 内存缓存，`os_unfair_lock` 保护，仅温路径写入、冷路径读取。

```swift
struct AppMetadata {
    let displayName: String
    let iconData: Data?          // PNG 编码，线程安全；NSImage 在主线程按需解码
}

final class AppMetadataStore {
    func record(_ metadata: AppMetadata, forBundleID: String)
    func metadata(forBundleID: String) -> AppMetadata?
}
```

### 4.5 `KeyEventTap`（全局键盘监听）

`Sources/KeyboardHitCounterCore/KeyEventTap.swift`

- `CGEvent.tapCreate` 使用 `.cgSessionEventTap` + `.headInsertEventTap` + `.listenOnly`，事件匹配 `keyDown`。
- 挂到独立线程的高优先级 `CFRunLoop`（`userInteractive` QoS），不挂主线程。
- 回调闭包只调用 `CounterStore.incrementCurrentSlot()`。
- 对外接口：

```swift
final class KeyEventTap {
    init(handler: @escaping () -> Void)
    func start() -> Result<Void, TapError>
    func stop()

    enum TapError: Error {
        case notTrusted          // 未授予辅助功能权限
        case failedToCreate
    }
}
```

### 4.6 `PersistenceStore`（持久化 I/O）

`Sources/KeyboardHitCounterCore/PersistenceStore.swift`

- 纯 I/O 与数据模型层：负责 `DailyCounts` 的读盘、累加、写盘。**不含节流与 delta 计算**（见 4.6.1 `PersistenceWorker`）。
- 对外接口：

```swift
struct DailyCounts: Codable {
    var version: Int = 1
    var days: [String: [String: Int64]] = [:]   // dayKey "yyyy-MM-dd" -> bundleID -> 累计计数
}

final class PersistenceStore {
    init(fileURL: URL)
    func load() -> DailyCounts                   // 启动时读盘，失败返回空
    func accumulate(deltas: [String: Int64], dayKey: String) // 累加进指定日
    func save() throws                           // 写 JSON（原子写临时文件后替换）
}
```

### 4.6.1 `PersistenceWorker`（持久化调度）

`Sources/KeyboardHitCounterCore/PersistenceWorker.swift`

- 后台串行队列 + **固定 5 秒周期定时器**（非「仅变化时写」），加退出时 `flushNow()`。
- 采用**增量（delta）方案**保证无丢数：持有 `lastSnapshotBySlot: [Int64]`（与 slot 一一对应，新 slot 以 0 补齐）。每轮读取 `CounterStore.countsBySlot()`，对每个非 0 slot 计算 `delta = 当前 - lastSnapshot[slot]`，经 `AppSlotRegistry.bundleID(forSlot:)` 映射成 bundleID，调用 `PersistenceStore.accumulate(deltas:dayKey:)` 累加进当日桶，再 `save()`。**不重置热路径计数器**——按键若落在「读」与「更新 lastSnapshot」之间，会被下一轮 delta 捕获，无丢失。
- 对外接口：

```swift
final class PersistenceWorker {
    init(counters: CounterStore,
         registry: AppSlotRegistry,
         store: PersistenceStore)
    func start()
    func stop()
    func flushNow()                              // 退出时同步执行一次 delta 落盘
    func sessionDeltaByBundleID() -> [String: Int64]  // 未落盘增量（session − 已合并），供聚合展示
}
```

### 4.7 `Aggregator`（聚合）

`Sources/KeyboardHitCounterCore/Aggregator.swift`

- 后台定时 1 秒，合并「持久化累计 + 未落盘增量」产出 UI 列表快照。
- `todayCount = days[today][bundleID] + sessionDelta[bundleID]`
- `totalCount = Σ days[*][bundleID] + sessionDelta[bundleID]`
- 其中 `sessionDelta[bundleID]` = 本会话**尚未落盘**的增量（`session − 已合并`），由 `PersistenceWorker.sessionDeltaByBundleID()` 提供，避免重复累计已落盘部分。
- 对外接口：

```swift
struct AppRow: Identifiable {
    let id: String            // bundleID
    let bundleID: String
    let displayName: String
    let iconData: Data?       // PNG，UI 层在主线程解码为 NSImage
    let todayCount: Int64
    let totalCount: Int64
}

final class Aggregator {
    func produceRows(counts: DailyCounts,
                     sessionDeltaByBundleID: [String: Int64],
                     metadataByBundleID: [String: AppMetadata],
                     dayKey: String) -> [AppRow]
}
```

`AppMetadata` 定义见 4.4.1。`sessionDeltaByBundleID` 与 `metadataByBundleID` 由调用方（AppDelegate 装配层）在后台生成，`produceRows` 保持纯函数、可独立测试。

### 4.8 `StatusViewModel`（UI 状态）

`Sources/KeyboardHitCounter/StatusViewModel.swift`

```swift
@MainActor
final class StatusViewModel: ObservableObject {
    @Published var rows: [AppRow] = []
    @Published var permissionState: PermissionState
}

enum PermissionState { case unknown, denied, granted }
```

### 4.9 `MenuBarController` / `StatusView`

`Sources/KeyboardHitCounter/MenuBarController.swift`、`StatusView.swift`

- `NSStatusItem`（菜单栏图标）+ `NSPopover` 承载 SwiftUI `StatusView`。
- `StatusView` 渲染 `StatusViewModel.rows`，在主线程把 `iconData` 解码为 `NSImage`；`denied` 状态显示「未开启辅助功能权限」提示与「打开系统设置」按钮。

### 4.10 `AppDelegate`

`Sources/KeyboardHitCounter/AppDelegate.swift`

- 装配所有模块、启动 tap、注册定时器（1 秒聚合 / 5 秒持久化）、监听 `applicationWillTerminate` 做最终 flush。
- 应用生命周期入口（`@main`），`LSUIElement` 由 `Info.plist` 控制。

## 5. 线程与异步模型

| 组件 | 运行位置 | 说明 |
|---|---|---|
| `KeyEventTap` 回调 | 专用线程 + 独立 `CFRunLoop`（`userInteractive`） | 唯一接触按键事件的代码 |
| `CounterStore` 热路径 | 同上 | 原子操作，无锁；数组启动时定容、永不移动 |
| `FrontmostAppTracker` | 主线程通知 / 后台兜底 | 更新 slot 与元数据，低频 |
| `AppSlotRegistry` | 温/冷路径（非热路径） | `os_unfair_lock`，低频，分配/反查 slot |
| `PersistenceWorker` | 后台串行队列 | 固定 5 秒周期 delta 落盘 + 退出 flush |
| `Aggregator` | 后台定时 1 秒 | 产出 `[AppRow]` |
| slot→bundleID 转换 | 后台（装配层，被 `PersistenceWorker` 与聚合层共用） | `CounterStore.countsBySlot()` + `AppSlotRegistry.bundleID(forSlot:)`，排除 slot 0 |
| `StatusViewModel` / UI | 主线程（`@MainActor`） | 只消费 `[AppRow]`，`iconData` 在主线程解码 |

**数据流：**

```
keydown → [系统不等待] → 回调：counter[slot] += 1（纳秒，wait-free）
                              ↓ 异步，与事件流完全无关
               Aggregator（1s）──► rows ──► UI
               PersistenceWorker（5s）──► counts.json
```

## 6. 数据模型

`~/Library/Application Support/KeyboardHitCounter/counts.json`：

```json
{
  "version": 1,
  "days": {
    "2026-08-18": {
      "com.apple.Safari": 1234,
      "com.googlecode.iterm2": 567
    }
  }
}
```

- `dayKey` 为本地时区的 `yyyy-MM-dd`。
- bundleID 为稳定键，显示名/图标仅用于展示、不参与持久化。
- **跨午夜边界**：日归属以「快照发生时刻」的 `dayKey` 为准。因持久化为固定 5 秒周期定时器，午夜前后的按键归属存在最多 5 秒粒度误差。对按键计数场景可接受，不做精确到毫秒的日切分。

## 7. 权限

- 依赖 macOS「辅助功能（Accessibility）」权限：`AXIsProcessTrusted()` 判断。
- 未授权时 `CGEvent.tapCreate` 返回 `nil`，`KeyEventTap.start()` 返回 `.notTrusted`，菜单栏显示引导。
- 「打开系统设置」通过 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` 跳转。
- 授权后重新调用 `start()` 恢复监听。

## 8. 错误处理

| 场景 | 处理 |
|---|---|
| 权限未授予 | UI 显示 denied 引导，不崩溃，授权后恢复 |
| tap 创建失败（非权限原因） | 返回 `.failedToCreate`，UI 显示错误态 |
| tap 被系统超时禁用 | 尝试重新 enable |
| 持久化读盘失败 | 视为空数据，不崩溃 |
| 持久化写盘失败 | 记录日志，保留内存数据，下轮重试 |
| 磁盘无 Application Support 目录 | 启动时确保目录存在 |

## 9. 构建与打包

- `swift build` 产出可执行文件（`KeyboardHitCounter` 可执行目标，依赖 `KeyboardHitCounterCore` 与 `CAtomic`）。
- `make app` 组装 `KeyboardHitCounter.app`：
  - 复制可执行文件到 `Contents/MacOS/`。
  - 生成 `Contents/Info.plist`：`LSUIElement = true`（纯菜单栏，无 Dock 图标）、`CFBundleIdentifier = dev.local.KeyboardHitCounter`、`NSHighResolutionCapable`。
  - `codesign --force --deep --sign -` ad-hoc 签名（TCC 权限按 bundleID + 签名绑定）。
- `make run` 构建并启动。
- `make test` 运行 XCTest。

## 10. 测试

- **单元测试（XCTest）**：
  - `CounterStore`：slot 0 忽略语义、固定容量 `maxSlots` 边界、并发递增总数正确。
  - `AppSlotRegistry`：同 bundleID 返回同 slot、slot 0 映射 nil、槽位满返回 0。
  - `PersistenceStore`：JSON 编解码往返、`accumulate` 累加、当日桶写入、文件不存在返回空。
  - `PersistenceWorker`：delta 只落盘增量、连续两轮无重复计数、中途新增 slot 不丢数。
  - `Aggregator`：今日/累计计算、按今日降序排序、排除 slot 0。
- **手动验证**：`KeyEventTap` 与权限依赖系统，需手动验证授权流程与真实按键计数。

## 11. 明确不做（YAGNI）

- 不做按「按键类型」分类统计。
- 不做数据导出（CSV）。
- 不做多日历史图表 UI。
- 不做设置界面（计数口径、持久化间隔均写死为常量）。
- 不做开机自启、热键切换等。