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