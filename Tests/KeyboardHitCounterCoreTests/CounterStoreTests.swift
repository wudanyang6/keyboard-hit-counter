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