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