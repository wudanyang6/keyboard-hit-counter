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