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
        components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(PersistenceWorker.dayKey(now: date), "2026-08-18")
    }
}