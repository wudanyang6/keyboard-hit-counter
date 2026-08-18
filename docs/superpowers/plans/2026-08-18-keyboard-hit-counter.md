# Keyboard Hit Counter 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个常驻 macOS 菜单栏的按键计数工具，记录每个前台应用的 keydown 次数，按天持久化，热路径对输入零阻塞。

**Architecture:** SwiftPM 四目标（C 原子原语 + 核心库 + 可执行 UI + 测试）。`CGEventTap` listenOnly 在专用线程上做无锁原子计数；后台 `PersistenceWorker` 用 delta 方案落盘，`Aggregator` 每秒合并未落盘增量产出 UI 列表。

**Tech Stack:** Swift 5（Swift 6 工具链）、SwiftUI + AppKit、CoreGraphics/Quartz `CGEventTap`、`NSWorkspace`、C11 `_Atomic`、SwiftPM + Makefile，零第三方依赖。

**Spec:** `docs/superpowers/specs/2026-08-18-keyboard-hit-counter-design.md`

## Global Constraints

- 最低 macOS 13（Ventura），`swift-tools-version: 5.9`（Swift 5 语言模式）
- 零第三方依赖（仅系统框架 + Swift 标准库）
- bundleID 稳定键：`dev.local.KeyboardHitCounter`
- `CounterStore.maxSlots = 512`；slot 0 = 忽略/未知；运行期永不扩容
- 持久化固定 5 秒周期，聚合固定 1 秒周期
- **核心库 `KeyboardHitCounterCore` 所有被可执行/测试目标引用的类型与成员必须是 `public`**
- 所有工具路径用绝对路径（用户规则）
- 工作目录：`/Users/wudanyang/workspace/keyboard-hit-counter`

---

## Task 1: SwiftPM 脚手架

**Files:**
- Create: `Package.swift`
- Create: `Sources/CAtomic/include/atomic_counter.h`
- Create: `Sources/CAtomic/atomic_counter.c`
- Create: `Sources/KeyboardHitCounterCore/Core.swift`
- Create: `Sources/KeyboardHitCounter/KeyboardHitCounterApp.swift`
- Create: `Tests/KeyboardHitCounterCoreTests/ScaffoldTests.swift`

**Interfaces:**
- Produces: 可编译运行的四目标包结构；`CAtomic` 模块名、`KeyboardHitCounterCore` 模块名、`KeyboardHitCounter` 可执行名、`KeyboardHitCounterCoreTests` 测试模块名（后续所有任务依赖这些名字）

- [ ] **Step 1: 写 `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardHitCounter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CAtomic"),
        .target(
            name: "KeyboardHitCounterCore",
            dependencies: ["CAtomic"]
        ),
        .executableTarget(
            name: "KeyboardHitCounter",
            dependencies: ["KeyboardHitCounterCore"]
        ),
        .testTarget(
            name: "KeyboardHitCounterCoreTests",
            dependencies: ["KeyboardHitCounterCore", "CAtomic"]
        ),
    ]
)
```

- [ ] **Step 2: 写 C 目标占位（空头文件 + 空实现，Task 2 会填充真实内容）**

`Sources/CAtomic/include/atomic_counter.h`：

```c
#ifndef ATOMIC_COUNTER_H
#define ATOMIC_COUNTER_H
#include <stdint.h>

typedef struct khc_counters khc_counters_t;

void *khc_counters_create(int64_t capacity);
void khc_counters_destroy(void *handle);
int64_t khc_counters_increment_current(void *handle);
int64_t khc_counters_load(const void *handle, int64_t slot);
void khc_counters_set_current_slot(void *handle, int64_t slot);
int64_t khc_counters_current_slot(const void *handle);
int64_t khc_counters_capacity(const void *handle);

#endif
```

`Sources/CAtomic/atomic_counter.c`（占位，编译通过即可；Task 2 替换）：

```c
#include "atomic_counter.h"
#include <stdlib.h>

void *khc_counters_create(int64_t capacity) { return NULL; }
void khc_counters_destroy(void *handle) { (void)handle; }
int64_t khc_counters_increment_current(void *handle) { (void)handle; return 0; }
int64_t khc_counters_load(const void *handle, int64_t slot) { (void)handle; (void)slot; return 0; }
void khc_counters_set_current_slot(void *handle, int64_t slot) { (void)handle; (void)slot; }
int64_t khc_counters_current_slot(const void *handle) { (void)handle; return 0; }
int64_t khc_counters_capacity(const void *handle) { (void)handle; return 0; }
```

- [ ] **Step 3: 写核心库占位**

`Sources/KeyboardHitCounterCore/Core.swift`：

```swift
import Foundation

/// 核心库占位。后续任务将在此目标中新增真实模块。
public enum CoreMarker {
    public static let version = 1
}
```

- [ ] **Step 4: 写可执行目标占位入口**

`Sources/KeyboardHitCounter/KeyboardHitCounterApp.swift`：

```swift
import Foundation

@main
struct KeyboardHitCounterApp {
    static func main() {
        print("KeyboardHitCounter scaffold")
    }
}
```

- [ ] **Step 5: 写占位测试**

`Tests/KeyboardHitCounterCoreTests/ScaffoldTests.swift`：

```swift
import XCTest
@testable import KeyboardHitCounterCore

final class ScaffoldTests: XCTestCase {
    func testScaffoldCompiles() {
        XCTAssertEqual(CoreMarker.version, 1)
    }
}
```

- [ ] **Step 6: 构建并跑测试**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift build 2>&1 | tail -5
swift test 2>&1 | tail -15
```

Expected: build 成功，`ScaffoldTests` PASS。

- [ ] **Step 7: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
chore: scaffold SwiftPM package

EOF
)"
```

---

## Task 2: CAtomic 锁无关计数原语

**Files:**
- Modify: `Sources/CAtomic/atomic_counter.c`
- Test: `Tests/KeyboardHitCounterCoreTests/CAtomicTests.swift`

**Interfaces:**
- Produces: C 函数 `khc_counters_create/destroy/increment_current/load/set_current_slot/current_slot/capacity`，头文件签名已在 Task 1 固定；Swift 侧 `import CAtomic` 后调用这些函数（`void*` 导入为 `UnsafeMutableRawPointer?`）

- [ ] **Step 1: 写失败测试**

`Tests/KeyboardHitCounterCoreTests/CAtomicTests.swift`：

```swift
import XCTest
import CAtomic

final class CAtomicTests: XCTestCase {
    func testCreateIncrementLoad() {
        let c = khc_counters_create(4)
        XCTAssertNotNil(c, "create 不应返回 nil")
        defer { khc_counters_destroy(c) }

        XCTAssertEqual(khc_counters_capacity(c), 4)
        XCTAssertEqual(khc_counters_current_slot(c), 0)

        khc_counters_set_current_slot(c, 1)
        XCTAssertEqual(khc_counters_current_slot(c), 1)

        XCTAssertEqual(khc_counters_increment_current(c), 1)
        XCTAssertEqual(khc_counters_increment_current(c), 2)
        XCTAssertEqual(khc_counters_load(c, 1), 2)
        XCTAssertEqual(khc_counters_load(c, 0), 0)
    }

    func testInvalidSlotLoadReturnsZero() {
        let c = khc_counters_create(2)
        defer { khc_counters_destroy(c) }
        XCTAssertEqual(khc_counters_load(c, -1), 0)
        XCTAssertEqual(khc_counters_load(c, 5), 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter CAtomicTests 2>&1 | tail -20
```

Expected: 断言失败（占位实现返回 0 / nil 语义不符）。

- [ ] **Step 3: 实现**

`Sources/CAtomic/atomic_counter.c`：

```c
#include "atomic_counter.h"
#include <stdatomic.h>
#include <stdlib.h>

struct khc_counters {
    _Atomic(int64_t) current_slot;
    int64_t capacity;
    _Atomic(int64_t) slots[];
};

void *khc_counters_create(int64_t capacity) {
    if (capacity <= 0) {
        return NULL;
    }
    size_t size = sizeof(struct khc_counters) + (size_t)capacity * sizeof(_Atomic(int64_t));
    struct khc_counters *c = (struct khc_counters *)calloc(1, size);
    if (c == NULL) {
        return NULL;
    }
    c->capacity = capacity;
    atomic_store_explicit(&c->current_slot, 0, memory_order_relaxed);
    return c;
}

void khc_counters_destroy(void *handle) {
    free(handle);
}

int64_t khc_counters_increment_current(void *handle) {
    struct khc_counters *c = (struct khc_counters *)handle;
    int64_t slot = atomic_load_explicit(&c->current_slot, memory_order_relaxed);
    return atomic_fetch_add_explicit(&c->slots[slot], 1, memory_order_relaxed) + 1;
}

int64_t khc_counters_load(const void *handle, int64_t slot) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    if (slot < 0 || slot >= c->capacity) {
        return 0;
    }
    return atomic_load_explicit(&c->slots[slot], memory_order_relaxed);
}

void khc_counters_set_current_slot(void *handle, int64_t slot) {
    struct khc_counters *c = (struct khc_counters *)handle;
    atomic_store_explicit(&c->current_slot, slot, memory_order_relaxed);
}

int64_t khc_counters_current_slot(const void *handle) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    return atomic_load_explicit(&c->current_slot, memory_order_relaxed);
}

int64_t khc_counters_capacity(const void *handle) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    return c->capacity;
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter CAtomicTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add lock-free atomic counters

EOF
)"
```

---

## Task 3: CounterStore（锁无关计数封装）

**Files:**
- Create: `Sources/KeyboardHitCounterCore/CounterStore.swift`
- Test: `Tests/KeyboardHitCounterCoreTests/CounterStoreTests.swift`

**Interfaces:**
- Consumes: `import CAtomic` 的 `khc_counters_*` 函数
- Produces: `public final class CounterStore`，`public static let maxSlots = 512`，`public init?()`，`public func incrementCurrentSlot()`，`public func setCurrentSlot(_:)`，`public func currentSlot() -> Int`，`public func countsBySlot() -> [Int64]`

- [ ] **Step 1: 写失败测试**

`Tests/KeyboardHitCounterCoreTests/CounterStoreTests.swift`：

```swift
import XCTest
@testable import KeyboardHitCounterCore

final class CounterStoreTests: XCTestCase {
    func testIncrementCurrentSlot() {
        let store = CounterStore()!
        store.setCurrentSlot(1)
        store.incrementCurrentSlot()
        store.incrementCurrentSlot()
        XCTAssertEqual(store.countsBySlot()[1], 2)
    }

    func testSlotZeroIsIgnoredSemantically() {
        let store = CounterStore()!
        store.setCurrentSlot(0)
        store.incrementCurrentSlot()
        XCTAssertEqual(store.countsBySlot()[0], 1)
        XCTAssertEqual(store.currentSlot(), 0)
    }

    func testCapacityIsFixed() {
        let store = CounterStore()!
        XCTAssertEqual(store.countsBySlot().count, CounterStore.maxSlots)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter CounterStoreTests 2>&1 | tail -15
```

Expected: 编译失败（`CounterStore` 未定义）。

- [ ] **Step 3: 实现**

`Sources/KeyboardHitCounterCore/CounterStore.swift`：

```swift
import CAtomic

/// 锁无关的按槽位计数器封装。
/// 线程安全由 C 侧 C11 原子保证，本类不含任何锁；数组启动时定容、运行期永不移动内存。
public final class CounterStore {
    public static let maxSlots = 512

    private let counters: UnsafeMutableRawPointer

    public init?() {
        guard let counters = khc_counters_create(Int64(Self.maxSlots)) else {
            return nil
        }
        self.counters = counters
    }

    deinit {
        khc_counters_destroy(counters)
    }

    /// 热路径：把当前槽位计数原子 +1。无分支、无锁、无分配。
    public func incrementCurrentSlot() {
        _ = khc_counters_increment_current(counters)
    }

    /// 原子写入当前前台应用槽位（槽位 ∈ [0, maxSlots)）。
    public func setCurrentSlot(_ slot: Int) {
        khc_counters_set_current_slot(counters, Int64(slot))
    }

    /// 读取当前槽位（测试/诊断用）。
    public func currentSlot() -> Int {
        Int(khc_counters_current_slot(counters))
    }

    /// 后台：读全部槽位计数快照。
    public func countsBySlot() -> [Int64] {
        let capacity = Int(khc_counters_capacity(counters))
        return (0..<capacity).map { khc_counters_load(counters, Int64($0)) }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter CounterStoreTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: wrap lock-free counters in CounterStore

EOF
)"
```

---

## Task 4: AppSlotRegistry + AppMetadataStore

**Files:**
- Create: `Sources/KeyboardHitCounterCore/AppSlotRegistry.swift`
- Create: `Sources/KeyboardHitCounterCore/AppMetadataStore.swift`
- Test: `Tests/KeyboardHitCounterCoreTests/AppSlotRegistryTests.swift`

**Interfaces:**
- Consumes: `CounterStore.maxSlots`
- Produces: `public final class AppSlotRegistry { public func slot(forBundleID:) -> Int; public func bundleID(forSlot:) -> String? }`；`public struct AppMetadata { public let displayName: String; public let iconData: Data? }`；`public final class AppMetadataStore { public func record(_:forBundleID:); public func metadata(forBundleID:) -> AppMetadata?; public func snapshot() -> [String: AppMetadata] }`

- [ ] **Step 1: 写失败测试**

`Tests/KeyboardHitCounterCoreTests/AppSlotRegistryTests.swift`：

```swift
import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class AppSlotRegistryTests: XCTestCase {
    func testSameBundleIDReturnsSameSlot() {
        let registry = AppSlotRegistry()
        let a = registry.slot(forBundleID: "com.apple.Safari")
        let b = registry.slot(forBundleID: "com.apple.Safari")
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a, 0)
    }

    func testSlotZeroMapsToNil() {
        let registry = AppSlotRegistry()
        XCTAssertNil(registry.bundleID(forSlot: 0))
    }

    func testMetadataRoundTrip() {
        let store = AppMetadataStore()
        let metadata = AppMetadata(displayName: "Safari", iconData: Data([0x01, 0x02]))
        store.record(metadata, forBundleID: "com.apple.Safari")
        XCTAssertEqual(store.metadata(forBundleID: "com.apple.Safari")?.displayName, "Safari")
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter AppSlotRegistryTests 2>&1 | tail -15
```

Expected: 编译失败（类型未定义）。

- [ ] **Step 3: 实现**

`Sources/KeyboardHitCounterCore/AppSlotRegistry.swift`：

```swift
import os

/// bundleID 与槽位的运行时映射。非热路径，`os_unfair_lock` 保护，低频访问。
/// 槽位在 [1, CounterStore.maxSlots) 单调递增、运行期不复用；满后返回 0（忽略）。
public final class AppSlotRegistry {
    private var lock = os_unfair_lock()
    private var bundleIDToSlot: [String: Int] = [:]
    private var slotToBundleID: [Int: String] = [:]
    private var nextSlot = 1

    public init() {}

    public func slot(forBundleID id: String) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        if let existing = bundleIDToSlot[id] {
            return existing
        }
        guard nextSlot < CounterStore.maxSlots else {
            return 0
        }
        let slot = nextSlot
        nextSlot += 1
        bundleIDToSlot[id] = slot
        slotToBundleID[slot] = id
        return slot
    }

    public func bundleID(forSlot slot: Int) -> String? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return slotToBundleID[slot]
    }
}
```

`Sources/KeyboardHitCounterCore/AppMetadataStore.swift`：

```swift
import Foundation
import os

/// 应用显示名/图标缓存。`iconData` 存 PNG `Data`（线程安全），`NSImage` 由 UI 主线程按需解码。
public struct AppMetadata {
    public let displayName: String
    public let iconData: Data?

    public init(displayName: String, iconData: Data?) {
        self.displayName = displayName
        self.iconData = iconData
    }
}

public final class AppMetadataStore {
    private var lock = os_unfair_lock()
    private var storage: [String: AppMetadata] = [:]

    public init() {}

    public func record(_ metadata: AppMetadata, forBundleID id: String) {
        os_unfair_lock_lock(&lock)
        storage[id] = metadata
        os_unfair_lock_unlock(&lock)
    }

    public func metadata(forBundleID id: String) -> AppMetadata? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage[id]
    }

    public func snapshot() -> [String: AppMetadata] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storage
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter AppSlotRegistryTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add slot registry and app metadata store

EOF
)"
```

---

## Task 5: DailyCounts + PersistenceStore

**Files:**
- Create: `Sources/KeyboardHitCounterCore/PersistenceStore.swift`
- Test: `Tests/KeyboardHitCounterCoreTests/PersistenceStoreTests.swift`

**Interfaces:**
- Produces: `public struct DailyCounts: Codable, Equatable { public var version: Int; public var days: [String: [String: Int64]]; public static let empty }`；`public final class PersistenceStore { public init(fileURL:); public func accumulate(deltas:dayKey:); public func snapshot() -> DailyCounts; public func save() throws }`

- [ ] **Step 1: 写失败测试**

`Tests/KeyboardHitCounterCoreTests/PersistenceStoreTests.swift`：

```swift
import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class PersistenceStoreTests: XCTestCase {
    func testAccumulateAndSnapshot() {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PersistenceStore(fileURL: url)

        store.accumulate(deltas: ["com.a": 3, "com.b": 5], dayKey: "2026-08-18")
        store.accumulate(deltas: ["com.a": 2], dayKey: "2026-08-18")

        let counts = store.snapshot()
        XCTAssertEqual(counts.days["2026-08-18"]?["com.a"], 5)
        XCTAssertEqual(counts.days["2026-08-18"]?["com.b"], 5)
    }

    func testRoundTripPersists() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PersistenceStore(fileURL: url)
        store.accumulate(deltas: ["com.a": 7], dayKey: "2026-08-18")
        try store.save()

        let reloaded = PersistenceStore(fileURL: url)
        XCTAssertEqual(reloaded.snapshot().days["2026-08-18"]?["com.a"], 7)
    }

    func testLoadMissingFileReturnsEmpty() {
        let url = temporaryFileURL()
        let store = PersistenceStore(fileURL: url)
        XCTAssertEqual(store.snapshot(), DailyCounts.empty)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("khc-test-\(UUID().uuidString)")
            .appendingPathComponent("counts.json")
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter PersistenceStoreTests 2>&1 | tail -15
```

Expected: 编译失败（类型未定义）。

- [ ] **Step 3: 实现**

`Sources/KeyboardHitCounterCore/PersistenceStore.swift`：

```swift
import Foundation
import os

public struct DailyCounts: Codable, Equatable {
    public var version: Int = 1
    public var days: [String: [String: Int64]] = [:]

    public static let empty = DailyCounts()

    public init() {}
}

/// 持久化 I/O 层：读盘、累加、写盘。不含节流与 delta 计算（见 PersistenceWorker）。
public final class PersistenceStore {
    private let fileURL: URL
    private var lock = os_unfair_lock()
    private var counts: DailyCounts

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.counts = Self.load(from: fileURL)
    }

    public func accumulate(deltas: [String: Int64], dayKey: String) {
        os_unfair_lock_lock(&lock)
        for (bundleID, delta) in deltas where delta > 0 {
            counts.days[dayKey, default: [:]][bundleID, default: 0] += delta
        }
        os_unfair_lock_unlock(&lock)
    }

    public func snapshot() -> DailyCounts {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return counts
    }

    public func save() throws {
        os_unfair_lock_lock(&lock)
        let data = try JSONEncoder().encode(counts)
        os_unfair_lock_unlock(&lock)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> DailyCounts {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(DailyCounts.self, from: data)) ?? .empty
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter PersistenceStoreTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add daily counts persistence store

EOF
)"
```

---

## Task 6: Aggregator（聚合）

**Files:**
- Create: `Sources/KeyboardHitCounterCore/Aggregator.swift`
- Test: `Tests/KeyboardHitCounterCoreTests/AggregatorTests.swift`

**Interfaces:**
- Consumes: `DailyCounts`、`AppMetadata`
- Produces: `public struct AppRow: Identifiable { public let id/bundleID/displayName/iconData/todayCount/totalCount }`；`public final class Aggregator { public func produceRows(counts:sessionDeltaByBundleID:metadataByBundleID:dayKey:) -> [AppRow] }`

- [ ] **Step 1: 写失败测试**

`Tests/KeyboardHitCounterCoreTests/AggregatorTests.swift`：

```swift
import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class AggregatorTests: XCTestCase {
    func testTodayAndTotal() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.a": 100]
        counts.days["2026-08-17"] = ["com.a": 50]

        let rows = Aggregator().produceRows(
            counts: counts,
            sessionDeltaByBundleID: ["com.a": 10],
            metadataByBundleID: [:],
            dayKey: "2026-08-18"
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].todayCount, 110)
        XCTAssertEqual(rows[0].totalCount, 160)
    }

    func testSortByTodayDescending() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.a": 5, "com.b": 10]

        let rows = Aggregator().produceRows(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            dayKey: "2026-08-18"
        )

        XCTAssertEqual(rows.map(\.bundleID), ["com.b", "com.a"])
    }

    func testZeroRowsAreExcluded() {
        let rows = Aggregator().produceRows(
            counts: .empty,
            sessionDeltaByBundleID: ["com.empty": 0],
            metadataByBundleID: [:],
            dayKey: "2026-08-18"
        )
        XCTAssertTrue(rows.isEmpty)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter AggregatorTests 2>&1 | tail -15
```

Expected: 编译失败（类型未定义）。

- [ ] **Step 3: 实现**

`Sources/KeyboardHitCounterCore/Aggregator.swift`：

```swift
import Foundation

public struct AppRow: Identifiable {
    public let id: String
    public let bundleID: String
    public let displayName: String
    public let iconData: Data?
    public let todayCount: Int64
    public let totalCount: Int64

    public init(bundleID: String, displayName: String, iconData: Data?, todayCount: Int64, totalCount: Int64) {
        self.id = bundleID
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
        self.todayCount = todayCount
        self.totalCount = totalCount
    }
}

/// 合并「持久化累计 + 未落盘增量」产出 UI 列表快照。纯函数，可独立测试。
public final class Aggregator {
    public init() {}

    public func produceRows(
        counts: DailyCounts,
        sessionDeltaByBundleID: [String: Int64],
        metadataByBundleID: [String: AppMetadata],
        dayKey: String
    ) -> [AppRow] {
        var bundleIDs = Set(counts.days.values.flatMap { $0.keys })
        bundleIDs.formUnion(sessionDeltaByBundleID.keys)

        return bundleIDs.compactMap { bundleID in
            let persistedTotal = counts.days.values.reduce(Int64(0)) { $0 + ($1[bundleID] ?? 0) }
            let sessionDelta = sessionDeltaByBundleID[bundleID] ?? 0

            let todayCount = (counts.days[dayKey]?[bundleID] ?? 0) + sessionDelta
            let totalCount = persistedTotal + sessionDelta

            guard todayCount > 0 || totalCount > 0 else { return nil }

            let metadata = metadataByBundleID[bundleID]
            return AppRow(
                bundleID: bundleID,
                displayName: metadata?.displayName ?? bundleID,
                iconData: metadata?.iconData,
                todayCount: todayCount,
                totalCount: totalCount
            )
        }
        .sorted { $0.todayCount > $1.todayCount }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter AggregatorTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add aggregator for UI rows

EOF
)"
```

---

## Task 7: PersistenceWorker（delta 落盘）

**Files:**
- Create: `Sources/KeyboardHitCounterCore/PersistenceWorker.swift`
- Test: `Tests/KeyboardHitCounterCoreTests/PersistenceWorkerTests.swift`

**Interfaces:**
- Consumes: `CounterStore`、`AppSlotRegistry`、`PersistenceStore`
- Produces: `public final class PersistenceWorker { public init(counters:registry:store:); public func start(); public func stop(); public func flushNow(); public func sessionDeltaByBundleID() -> [String: Int64]; public static func dayKey(now:) -> String; public static func computeDeltas(current:merged:bundleIDForSlot:) -> (deltas: [String: Int64], merged: [Int64]) }`

- [ ] **Step 1: 写失败测试（针对纯函数 `computeDeltas` 与 `dayKey`）**

`Tests/KeyboardHitCounterCoreTests/PersistenceWorkerTests.swift`：

```swift
import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class PersistenceWorkerTests: XCTestCase {
    func testComputeDeltasOnlyReturnsIncrements() {
        let current: [Int64] = [0, 10, 5, 0]
        let merged: [Int64] = [0, 6, 5, 0]
        let slots = [1: "com.a", 2: "com.b"]

        let result = PersistenceWorker.computeDeltas(
            current: current,
            merged: merged,
            bundleIDForSlot: { slots[$0] }
        )

        XCTAssertEqual(result.deltas, ["com.a": 4])
        XCTAssertEqual(result.merged, [0, 10, 5, 0])
    }

    func testComputeDeltasExtendsMerged() {
        let current: [Int64] = [0, 3]
        let result = PersistenceWorker.computeDeltas(
            current: current,
            merged: [],
            bundleIDForSlot: { $0 == 1 ? "com.a" : nil }
        )
        XCTAssertEqual(result.deltas, ["com.a": 3])
        XCTAssertEqual(result.merged.count, 2)
    }

    func testDayKeyFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 18
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(PersistenceWorker.dayKey(now: date), "2026-08-18")
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter PersistenceWorkerTests 2>&1 | tail -15
```

Expected: 编译失败（`PersistenceWorker` 未定义）。

- [ ] **Step 3: 实现**

`Sources/KeyboardHitCounterCore/PersistenceWorker.swift`：

```swift
import Foundation

/// 后台串行队列 + 固定 5 秒周期定时器做 delta 落盘；退出时 flushNow()。
/// 不重置热路径计数器——按键若落在「读」与「更新 merged」之间，会被下一轮 delta 捕获，无丢失。
public final class PersistenceWorker {
    private let counters: CounterStore
    private let registry: AppSlotRegistry
    private let store: PersistenceStore

    private let queue = DispatchQueue(label: "khc.persistence", qos: .utility)
    private var mergedBySlot: [Int64] = []
    private var timer: DispatchSourceTimer?

    public init(counters: CounterStore,
                registry: AppSlotRegistry,
                store: PersistenceStore) {
        self.counters = counters
        self.registry = registry
        self.store = store
    }

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 退出时同步 flush。
    public func flushNow() {
        queue.sync { self.flush() }
    }

    /// 未落盘增量（session − 已合并），供聚合展示。只读，不推进 merged。
    public func sessionDeltaByBundleID() -> [String: Int64] {
        queue.sync {
            Self.computeDeltas(
                current: counters.countsBySlot(),
                merged: mergedBySlot,
                bundleIDForSlot: { [registry] slot in registry.bundleID(forSlot: slot) }
            ).deltas
        }
    }

    // MARK: - 内部

    private func flush() {
        let (deltas, merged) = Self.computeDeltas(
            current: counters.countsBySlot(),
            merged: mergedBySlot,
            bundleIDForSlot: { [registry] slot in registry.bundleID(forSlot: slot) }
        )
        mergedBySlot = merged
        store.accumulate(deltas: deltas, dayKey: Self.dayKey())
        try? store.save()
    }

    /// 纯函数：给定当前计数与已合并计数，返回 (增量, 新的已合并计数)。可独立测试。
    public static func computeDeltas(
        current: [Int64],
        merged: [Int64],
        bundleIDForSlot: (Int) -> String?
    ) -> (deltas: [String: Int64], merged: [Int64]) {
        var merged = merged
        while merged.count < current.count {
            merged.append(0)
        }

        var deltas: [String: Int64] = [:]
        for slot in 1..<current.count {
            let delta = current[slot] - merged[slot]
            merged[slot] = current[slot]
            guard delta > 0, let bundleID = bundleIDForSlot(slot) else { continue }
            deltas[bundleID, default: 0] += delta
        }
        return (deltas, merged)
    }

    public static func dayKey(now: Date = Date()) -> String {
        dayFormatter.string(from: now)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift test --filter PersistenceWorkerTests 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add delta-based persistence worker

EOF
)"
```

---

## Task 8: KeyEventTap（全局键盘监听）

**Files:**
- Create: `Sources/KeyboardHitCounterCore/KeyEventTap.swift`

**Interfaces:**
- Consumes: 无（只依赖系统框架）
- Produces: `public final class KeyEventTap { public init(handler: @escaping () -> Void); public func start() -> Result<Void, TapError>; public func stop(); public enum TapError: Error { case notTrusted, failedToCreate } }`

**验证方式：** 本组件依赖辅助功能权限与系统事件流，无法单测；验证标准为 `swift build` 通过 + 后续 Task 11 手动运行验证真实按键计数。

- [ ] **Step 1: 实现**

`Sources/KeyboardHitCounterCore/KeyEventTap.swift`：

```swift
import Foundation
import CoreFoundation
import CoreGraphics
import ApplicationServices

/// 全局键盘监听：listenOnly 事件 tap，挂专用高优先级线程。
/// 回调只调用 handler（即 CounterStore.incrementCurrentSlot），无锁、无分配。
public final class KeyEventTap {
    public enum TapError: Error {
        case notTrusted
        case failedToCreate
    }

    private let handler: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    public init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    public func start() -> Result<Void, TapError> {
        guard AXIsProcessTrusted() else {
            return .failure(.notTrusted)
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.keyDownCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .failure(.failedToCreate)
        }
        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return .failure(.failedToCreate)
        }
        runLoopSource = source

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "khc.event-tap"
        thread.start()

        return .success(())
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
    }

    /// 非捕获 C 回调：经 userInfo 取回 self 并调用 handler。listenOnly 下返回值被系统忽略。
    private static let keyDownCallback: CGEventTapCallBack = { _, _, _, userInfo in
        guard let userInfo else { return nil }
        let tap = Unmanaged<KeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        tap.handler()
        return nil
    }
}
```

- [ ] **Step 2: 构建**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift build 2>&1 | tail -15
```

Expected: 构建成功。

- [ ] **Step 3: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add listen-only global key event tap

EOF
)"
```

---

## Task 9: FrontmostAppTracker（前台应用追踪）

**Files:**
- Create: `Sources/KeyboardHitCounterCore/FrontmostAppTracker.swift`
- Create: `Sources/KeyboardHitCounterCore/NSImage+PNG.swift`

**Interfaces:**
- Consumes: `AppSlotRegistry`、`CounterStore`、`AppMetadataStore`
- Produces: `public final class FrontmostAppTracker { public init(registry:counters:metadataStore:); public func start(); public func stop() }`

**验证方式：** 依赖 `NSWorkspace`，无法单测；验证标准为 `swift build` 通过 + Task 11 手动验证。

- [ ] **Step 1: 实现 PNG 转换扩展**

`Sources/KeyboardHitCounterCore/NSImage+PNG.swift`：

```swift
import AppKit

public extension NSImage {
    /// 把图标转为 PNG Data（线程安全），供跨线程传递。
    func khcPNGData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 2: 实现**

`Sources/KeyboardHitCounterCore/FrontmostAppTracker.swift`：

```swift
import AppKit

/// 追踪最前台应用：订阅 NSWorkspace 通知，解析 bundleID → 分配 slot → 原子写入当前 slot，
/// 并把新出现应用的显示名/图标写入 AppMetadataStore。每秒兜底刷新防止漏通知。
public final class FrontmostAppTracker {
    private let registry: AppSlotRegistry
    private let counters: CounterStore
    private let metadataStore: AppMetadataStore
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    public init(registry: AppSlotRegistry,
                counters: CounterStore,
                metadataStore: AppMetadataStore) {
        self.registry = registry
        self.counters = counters
        self.metadataStore = metadataStore
    }

    public func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.apply(app)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            self?.apply(app)
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        timer?.invalidate()
        timer = nil
    }

    private func apply(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Self.ownBundleID else {
            counters.setCurrentSlot(0)
            return
        }

        let slot = registry.slot(forBundleID: bundleID)
        counters.setCurrentSlot(slot)

        if metadataStore.metadata(forBundleID: bundleID) == nil {
            let metadata = AppMetadata(
                displayName: app.localizedName ?? bundleID,
                iconData: app.icon?.khcPNGData()
            )
            metadataStore.record(metadata, forBundleID: bundleID)
        }
    }

    private static let ownBundleID = Bundle.main.bundleIdentifier
}
```

- [ ] **Step 3: 构建**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift build 2>&1 | tail -15
```

Expected: 构建成功。

- [ ] **Step 4: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add frontmost app tracker

EOF
)"
```

---

## Task 10: 菜单栏 UI（StatusViewModel + StatusView + MenuBarController）

**Files:**
- Create: `Sources/KeyboardHitCounter/StatusViewModel.swift`
- Create: `Sources/KeyboardHitCounter/StatusView.swift`
- Create: `Sources/KeyboardHitCounter/MenuBarController.swift`

**Interfaces:**
- Consumes: `AppRow`、`AppMetadata`（来自 Core）
- Produces: `@MainActor final class StatusViewModel: ObservableObject { @Published var rows: [AppRow]; @Published var permissionState: PermissionState }`；`enum PermissionState { case unknown, denied, granted }`；`struct StatusView: View`；`final class MenuBarController: NSObject`

**验证方式：** `swift build` 通过（Task 11 装配后手动验证 UI）。

- [ ] **Step 1: 实现 `StatusViewModel`**

`Sources/KeyboardHitCounter/StatusViewModel.swift`：

```swift
import Foundation
import Combine
import KeyboardHitCounterCore

public enum PermissionState {
    case unknown
    case denied
    case granted
}

@MainActor
public final class StatusViewModel: ObservableObject {
    @Published public var rows: [AppRow] = []
    @Published public var permissionState: PermissionState = .unknown

    public init() {}
}
```

- [ ] **Step 2: 实现 `StatusView`**

`Sources/KeyboardHitCounter/StatusView.swift`：

```swift
import SwiftUI
import AppKit
import KeyboardHitCounterCore

public struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel
    let onOpenSettings: () -> Void

    public init(viewModel: StatusViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.permissionState == .denied {
                deniedView
            } else if viewModel.rows.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .frame(width: 320)
        .padding(8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    RowView(row: row)
                }
            }
        }
    }

    private var emptyView: some View {
        Text("暂无记录")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要「辅助功能」权限").font(.headline)
            Text("用于监听全局键盘事件，授权后自动开始计数。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("打开系统设置", action: onOpenSettings)
        }
        .padding(.vertical, 8)
    }
}

private struct RowView: View {
    let row: AppRow

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).lineLimit(1)
                Text("累计 \(row.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(row.todayCount)")
                .font(.system(.headline, design: .monospaced))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var icon: some View {
        if let data = row.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
```

- [ ] **Step 3: 实现 `MenuBarController`**

`Sources/KeyboardHitCounter/MenuBarController.swift`：

```swift
import AppKit
import SwiftUI

public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: StatusViewModel

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "Keyboard Hit Counter"
            )
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusView(viewModel: viewModel) { [weak self] in
                self?.openAccessibilitySettings()
            }
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: 构建**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift build 2>&1 | tail -15
```

Expected: 构建成功。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: add menu bar UI

EOF
)"
```

---

## Task 11: AppDelegate 装配与应用入口

**Files:**
- Create: `Sources/KeyboardHitCounter/AppDelegate.swift`
- Modify: `Sources/KeyboardHitCounter/KeyboardHitCounterApp.swift`（替换 Task 1 占位入口）

**Interfaces:**
- Consumes: Core 全部公开类型
- Produces: 可运行的应用（`swift build` 成功；`swift run` 可启动菜单栏图标）

**验证方式：** `swift run` 后菜单栏出现键盘图标；点击弹出列表；首次运行显示「需要辅助功能权限」引导（因为尚未授权）。

- [ ] **Step 1: 实现 `AppDelegate`**

`Sources/KeyboardHitCounter/AppDelegate.swift`：

```swift
import AppKit
import KeyboardHitCounterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let counters = CounterStore()!
    private let registry = AppSlotRegistry()
    private let metadataStore = AppMetadataStore()
    private lazy var persistenceStore = PersistenceStore(fileURL: Self.countsFileURL)
    private lazy var persistenceWorker = PersistenceWorker(
        counters: counters, registry: registry, store: persistenceStore
    )
    private lazy var tracker = FrontmostAppTracker(
        registry: registry, counters: counters, metadataStore: metadataStore
    )
    private let viewModel = StatusViewModel()
    private let uiQueue = DispatchQueue(label: "khc.ui", qos: .userInitiated)
    private var aggregatorTimer: DispatchSourceTimer?
    private var tap: KeyEventTap?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startTap()
        startWorkers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistenceWorker.flushNow()
        tap?.stop()
        tracker.stop()
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController(viewModel: viewModel)
    }

    private func startTap() {
        tap = KeyEventTap { [weak self] in
            self?.counters.incrementCurrentSlot()
        }
        switch tap?.start() {
        case .success:
            viewModel.permissionState = .granted
        case .failure(.notTrusted), .failure(.failedToCreate), .none:
            viewModel.permissionState = .denied
        }
    }

    private func startWorkers() {
        tracker.start()
        persistenceWorker.start()

        let timer = DispatchSource.makeTimerSource(queue: uiQueue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.refreshUI() }
        timer.resume()
        aggregatorTimer = timer
    }

    private func refreshUI() {
        let counts = persistenceStore.snapshot()
        let sessionDelta = persistenceWorker.sessionDeltaByBundleID()
        let metadata = metadataStore.snapshot()
        let rows = Aggregator().produceRows(
            counts: counts,
            sessionDeltaByBundleID: sessionDelta,
            metadataByBundleID: metadata,
            dayKey: PersistenceWorker.dayKey()
        )

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.rows = rows
        }
    }

    private static var countsFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("KeyboardHitCounter", isDirectory: true)
            .appendingPathComponent("counts.json")
    }
}
```

- [ ] **Step 2: 替换入口为 SwiftUI App 生命周期**

`Sources/KeyboardHitCounter/KeyboardHitCounterApp.swift`：

```swift
import SwiftUI

@main
struct KeyboardHitCounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: 构建**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && swift build 2>&1 | tail -20
```

Expected: 构建成功。

- [ ] **Step 4: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
feat: wire app delegate and entry point

EOF
)"
```

---

## Task 12: 打包（Info.plist + Makefile）与 README

**Files:**
- Create: `Resources/Info.plist`
- Create: `Makefile`
- Create: `README.md`

**Interfaces:**
- Produces: `make app` 生成 `build/KeyboardHitCounter.app`（ad-hoc 签名）；`make run` 构建并启动；`make test` 跑测试

**验证方式：** `make app` 成功生成 `.app`；`make run` 启动后菜单栏出现图标。

- [ ] **Step 1: 写 `Info.plist`**

`Resources/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>KeyboardHitCounter</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.KeyboardHitCounter</string>
    <key>CFBundleExecutable</key>
    <string>KeyboardHitCounter</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 2: 写 `Makefile`**

```makefile
APP_NAME := KeyboardHitCounter
APP_DIR := build/$(APP_NAME).app
BIN_DIR := .build/release
RESOURCES := Resources

.PHONY: build app run test clean

build:
	swift build -c release

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/"
	cp "$(RESOURCES)/Info.plist" "$(APP_DIR)/Contents/"
	codesign --force --deep --sign - "$(APP_DIR)"

run: app
	open "$(APP_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf build
```

- [ ] **Step 3: 写 `README.md`**

```markdown
# Keyboard Hit Counter

常驻 macOS 菜单栏的按键计数工具：记录每个前台应用的键盘敲击次数，按天累计并本地持久化。热路径使用 listenOnly 事件 tap + 无锁原子计数，对输入零阻塞。

## 构建与运行

```bash
make run      # 构建 release 并打包 .app 后启动
make app      # 只打包 build/KeyboardHitCounter.app
make test     # 运行单元测试
```

## 权限

首次运行需在「系统设置 → 隐私与安全性 → 辅助功能」中勾选本应用，之后自动开始计数。计数数据保存在 `~/Library/Application Support/KeyboardHitCounter/counts.json`。
```

- [ ] **Step 4: 打包验证**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && make app 2>&1 | tail -20 && ls -la build/KeyboardHitCounter.app/Contents/MacOS
```

Expected: 生成 `.app`，`Contents/MacOS/KeyboardHitCounter` 存在。

- [ ] **Step 5: 提交**

```bash
cd /Users/wudanyang/workspace/keyboard-hit-counter && git add -A && git commit -m "$(cat <<'EOF'
chore: add app packaging and README

EOF
)"
```

---

## 手动验证清单（Task 12 之后执行）

1. `make run` 启动，菜单栏出现键盘图标。
2. 首次点击图标 → 显示「需要辅助功能权限」，点「打开系统设置」。
3. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 `KeyboardHitCounter`。
4. 重启应用（勾选后可能需重启应用以生效）。
5. 在任意应用（Safari、终端、Xcode 等）打字，切换到其它应用继续打字。
6. 点击菜单栏图标，验证各应用今日计数递增、按今日降序、图标正确。
7. 退出应用再启动，验证同日累计数据保留（`counts.json` 已写盘）。
8. 打字过程中确认输入无卡顿、无延迟。