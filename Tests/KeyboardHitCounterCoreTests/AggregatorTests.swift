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

    func testEqualTodayCountsOrderedStablyByBundleID() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.b": 5, "com.a": 5]

        let rows = Aggregator().produceRows(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            dayKey: "2026-08-18"
        )

        XCTAssertEqual(rows.map(\.bundleID), ["com.a", "com.b"])
    }
}