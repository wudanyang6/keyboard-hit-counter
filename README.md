# Keyboard Hit Counter

常驻 macOS 菜单栏的按键计数工具：按前台应用统计键盘敲击次数，按天累计，只存本地。

[![CI](https://github.com/wudanyang6/keyboard-hit-counter/actions/workflows/ci.yml/badge.svg)](https://github.com/wudanyang6/keyboard-hit-counter/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

<!-- 建议在此处放一张菜单栏 popover + 统计窗口的截图 -->

## 隐私边界

这个工具需要「辅助功能」权限来监听全局键盘事件，所以你应该先知道它到底看了什么：

- **只数次数，不看内容。** 事件回调拿到 `CGEvent` 后直接丢弃，从不读取 keycode、字符或修饰键——见 [`KeyEventTap.swift:74-79`](Sources/KeyboardHitCounterCore/KeyEventTap.swift)，回调的三个参数全部是 `_`。
- **落盘的数据只有三样东西**：日期、应用 bundle ID、当天次数。数据结构就是 `[日期: [bundleID: 次数]]`，见 [`PersistenceStore.swift:4-11`](Sources/KeyboardHitCounterCore/PersistenceStore.swift)。
- **不联网。** 代码中没有任何网络请求，数据只写到你自己的磁盘。
- **只监听按下（`keyDown`），且是 `listenOnly` 模式**——无法修改或拦截你的输入。

不放心的话，需要审查的核心文件只有两个，加起来不到 140 行。

## 功能

- 菜单栏图标，左键点开当天各应用的敲击排行。
- 右键 → 「统计…」打开统计窗口，含每日 / 每周 / 总计三个视图与堆叠柱状趋势图。
- 每 5 秒增量落盘，退出时 flush，不丢数据。
- 热路径（按键回调）只做一次原子自增，不分配内存、不加锁、不做 I/O，对输入零阻塞。

## 系统要求

- macOS 13 Ventura 或更高（统计图表依赖系统 `Charts` 框架）。
- 从源码构建还需要 Xcode 15+ 或对应的 Swift 5.9+ 工具链（`swift --version` 可查）。
- Intel 与 Apple Silicon 都支持，Release 产物是通用二进制。

## 安装

### 方式一：下载现成的（无需 Xcode）

1. 从 [Releases](https://github.com/wudanyang6/keyboard-hit-counter/releases) 下载 `KeyboardHitCounter.zip`。
2. 解压，把 `KeyboardHitCounter.app` 拖进「应用程序」。
3. **解除 Gatekeeper 隔离**——本项目是 ad-hoc 签名、未经 Apple 公证，从网上下载的 app 会被系统直接拦下并提示「已损坏」或「无法验证开发者」：

   ```bash
   xattr -dr com.apple.quarantine /Applications/KeyboardHitCounter.app
   ```

   这一步是必需的，不是可选优化。跳过它 app 打不开。

### 方式二：从源码构建

```bash
git clone https://github.com/wudanyang6/keyboard-hit-counter.git
cd keyboard-hit-counter
make run
```

自己构建出来的 app 不带隔离标记，不需要上面的 `xattr` 步骤。

## 首次运行：授予辅助功能权限

启动后菜单栏会出现图标，并弹出「需要「辅助功能」权限」提示：

1. 点提示里的「打开系统设置」，或手动进入 **系统设置 → 隐私与安全性 → 辅助功能**。
2. 勾选 `KeyboardHitCounter`。
3. 不用重启 app——它每秒检查一次授权状态，勾选后会自动接上事件监听并开始计数。

如果列表里没有它，点 `+` 手动添加 `/Applications/KeyboardHitCounter.app`。

## 数据存放与卸载

计数文件在：

```
~/Library/Application Support/KeyboardHitCounter/counts.json
```

完整卸载（删 app + 删数据 + 撤权限）：

```bash
rm -rf /Applications/KeyboardHitCounter.app
rm -rf ~/Library/Application\ Support/KeyboardHitCounter
```

然后在「系统设置 → 隐私与安全性 → 辅助功能」里把它移出列表。

## 开发

```bash
make build            # 只构建宿主架构，开发迭代用，比通用构建快
make build-universal  # Intel + Apple Silicon 通用二进制
make app              # 组装 build/KeyboardHitCounter.app（通用二进制 + ad-hoc 签名）
make zip              # 打出可分发的 build/KeyboardHitCounter.zip
make run              # app + 启动
make test             # swift test
make icon             # 从 Scripts/render_icon.swift 重新生成 .icns
make clean
```

跑单个测试：`swift test --filter StatsAggregatorTests` 或 `swift test --filter StatsAggregatorTests/testTodayWeekTotalSums`。

`swift run` 会绕过 Info.plist 直接跑裸可执行文件，缺少 `LSUIElement` 和 bundle ID，权限相关的行为不对——涉及权限时请用 `make run`。

## 架构

严格的热 / 温 / 冷三层切分：

| 层 | 组件 | 职责 |
|---|---|---|
| 热 | `KeyEventTap` → `CounterStore` | 按键回调，单次原子自增，无锁无分配无 I/O |
| 温 | `FrontmostAppTracker` + `AppSlotRegistry` | 应用切换时把 bundle ID 映射为槽位并原子写入 |
| 冷 | `PersistenceWorker` + `PersistenceStore` | 后台队列 5 秒一次增量落盘 |

可单测的逻辑全部在 `KeyboardHitCounterCore`，可执行 target 只是 UI 装配层（SwiftPM 的测试 target 无法 import 可执行 target）。

设计原理与取舍见 [`docs/superpowers/specs/2026-08-18-keyboard-hit-counter-design.md`](docs/superpowers/specs/2026-08-18-keyboard-hit-counter-design.md)，需要维持的不变量见 [`CLAUDE.md`](CLAUDE.md)。

## License

[GPL-3.0](LICENSE)
