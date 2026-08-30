# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu bar app (menulet) that counts keyboard hits per frontmost app, accumulates them per day, and persists locally. The hot path (the `keyDown` event callback) must never block input: it does a single atomic read + atomic increment and nothing else.

## Build, run, test

```bash
make build    # swift build -c release
make app      # assemble build/KeyboardHitCounter.app (ad-hoc codesign)
make run      # build + app + open the .app (menu bar icon appears)
make test     # swift test
make clean    # swift package clean && rm -rf build
```

- Single test: `swift test --filter <TestCaseClass>` or `swift test --filter <TestCaseClass>/<testMethod>`.
- `swift run` launches the raw executable without the Info.plist bundle — fine for quick checks, but the app depends on `LSUIElement` + bundle ID for TCC permission, so use `make run` for anything permission-related.
- The app needs macOS **Accessibility** permission. First launch shows a "需要「辅助功能」权限" prompt with an "打开系统设置" button; granting it in System Settings makes the tap auto-recover (AppDelegate polls `AXIsProcessTrusted()` every second and restarts the tap).

## Target layout (SwiftPM)

Four targets, defined in `Package.swift` (`swift-tools-version: 5.9`, `platforms: [.macOS(.v13)]`, zero third-party deps):

| Target | Role |
|---|---|
| `CAtomic` | C11 `_Atomic(int64_t)` lock-free counter array, exposed to Swift as opaque `void*` handle. |
| `KeyboardHitCounterCore` | All logic: counting, slot registry, persistence, aggregation, event tap, frontmost-app tracking. Unit-testable via `import`. |
| `KeyboardHitCounter` | Executable + AppKit/SwiftUI UI layer (menu bar, status view, stats window). |
| `KeyboardHitCounterCoreTests` | XCTest for the Core library. |

**Rule:** SwiftPM test targets cannot import the executable target, so anything that needs unit testing lives in `KeyboardHitCounterCore` and must be `public`. The executable target is only a thin assembly/UI shell (`AppDelegate` wires everything together).

## Core architecture

The design is a strict hot/warm/cold split. The full rationale is in `docs/superpowers/specs/2026-08-18-keyboard-hit-counter-design.md`.

### Hot path (the only code that touches key events)

`KeyEventTap` → `CounterStore.incrementCurrentSlot()`.

- `KeyEventTap` (`Sources/KeyboardHitCounterCore/KeyEventTap.swift`): `CGEvent.tapCreate` with `.cgSessionEventTap` + `.headInsertEventTap` + `.listenOnly`, matching `keyDown` only. Runs on a dedicated high-priority (`userInteractive`) thread with its own `CFRunLoop`. The C callback calls back into the handler via `userInfo`; return value ignored under `listenOnly`.
- `CounterStore` (`Sources/KeyboardHitCounterCore/CounterStore.swift`) wraps `CAtomic`. The counter array is allocated once at startup (`maxSlots = 512`) and **never resized or moved at runtime** — this is the correctness premise for lock-free reads. `incrementCurrentSlot()` is branch-free: it increments `counter[currentSlot]`.

### Warm path (frontmost-app tracking)

`FrontmostAppTracker` (`Sources/KeyboardHitCounterCore/FrontmostAppTracker.swift`) observes `NSWorkspace.didActivateApplicationNotification` plus a 1-second fallback poll. On app switch it maps `bundleID → slot` via `AppSlotRegistry`, then atomically writes `CounterStore.setCurrentSlot(slot)`. Newly-seen apps have displayName + icon PNG `Data` cached in `AppMetadataStore`.

- `AppSlotRegistry` (`Sources/KeyboardHitCounterCore/AppSlotRegistry.swift`): `os_unfair_lock`-guarded `bundleID ↔ slot` map. Slots allocated monotonically from `[1, maxSlots)`, never reused; full → returns `0`.
- **Slot 0 is "ignore/unknown"** — used when the frontmost app is unknown, is this app itself, or the registry is full. Its count is never mapped to any bundleID, so the hot path stays branch-free.

### Cold path (persistence + aggregation, background timers)

- `PersistenceWorker` (`Sources/KeyboardHitCounterCore/PersistenceWorker.swift`): serial background queue + fixed 5-second timer. **Delta scheme**: keeps `mergedBySlot` (last snapshot); each tick reads `countsBySlot()`, computes `delta = current - merged`, maps slots → bundleIDs, accumulates into the current day, saves. It never resets the hot-path counters, so keys pressed between "read" and "update merged" are caught by the next tick — no loss.
- `PersistenceStore` (`Sources/KeyboardHitCounterCore/PersistenceStore.swift`): pure I/O over `~/Library/Application Support/KeyboardHitCounter/counts.json`. Data model `DailyCounts { version, days: [dayKey "yyyy-MM-dd" : [bundleID : Int64]] }`. Load failure → empty; save is atomic-write.
- `Aggregator` / `StatsAggregator`: pure functions merging persisted totals + un-persisted session delta (from `sessionDeltaByBundleID()`), producing `[AppRow]` / `StatsSnapshot`. Both take everything as parameters and are independently unit-tested.

### Assembly (executable target)

`AppDelegate` (`Sources/KeyboardHitCounter/AppDelegate.swift`) is the composition root: it constructs the store/registry/worker/tracker/tap, starts the 1-second UI refresh timer and 5-second persistence timer, and flushes on `applicationWillTerminate`.

UI (main thread only):
- `MenuBarController` (`Sources/KeyboardHitCounter/MenuBarController.swift`): `NSStatusItem` + `NSPopover`. Left-click toggles the popover (`StatusView`); right-click shows a context menu with "统计…" (opens stats window) and "退出".
- `StatusView`/`StatusViewModel`: the popover list of today's counts (sorted by today descending). Decodes `iconData` → `NSImage` on the main thread.
- `StatsView`/`StatsViewModel`/`StatsWindowController`: a separate `NSWindow` with tabs (每日/每周/总计) and Swift `Charts` stacked bar trends, driven by `StatsAggregator`'s `StatsSnapshot`.

## Key invariants to preserve

- **Never add work to the `KeyEventTap` callback / `incrementCurrentSlot()`** — no allocation, no I/O, no string formatting, no lock, no dispatch. If a feature needs data at keypress time, it must be derived later from the counters.
- **`CounterStore` capacity is fixed at startup.** Do not resize/reallocate the counter array at runtime.
- **Every type the executable or test targets reference must be `public`** and live in `KeyboardHitCounterCore`.
- Day boundaries use the local-timezone `yyyy-MM-dd` (`PersistenceWorker.dayKey()`), keyed at snapshot time — persistence is a fixed 5s cadence, so around-midnight attribution is coarse by design (accepted, not a bug).
- UI state is only mutated on the main thread; `iconData` is passed as `Data` (thread-safe), never `NSImage` across threads.
