import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class StatsAggregatorTests: XCTestCase {
    private func date(_ dayKey: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.date(from: dayKey)!
    }

    func testTodayWeekTotalSums() {
        // 2026-08-18 是周二；同周内含 2026-08-17（周一）。
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.a": 100]
        counts.days["2026-08-17"] = ["com.a": 50]
        counts.days["2026-01-01"] = ["com.a": 20]

        let snapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            now: date("2026-08-18")
        )

        XCTAssertEqual(snapshot.todayRows.first?.count, 100)
        XCTAssertEqual(snapshot.weekRows.first?.count, 150)
        XCTAssertEqual(snapshot.totalRows.first?.count, 170)
    }

    func testWeekBoundaryAcrossSundayToMonday() {
        // 2026-08-16 周日, 2026-08-17 周一：属于不同的 ISO 周。
        var counts = DailyCounts()
        counts.days["2026-08-16"] = ["com.a": 10]
        counts.days["2026-08-17"] = ["com.a": 20]

        let snapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            now: date("2026-08-17")
        )

        XCTAssertEqual(snapshot.weekRows.first?.count, 20)
    }

    func testSessionDeltaAppliedToTodayWeekAndTotal() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.a": 100]

        let snapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: ["com.a": 5],
            metadataByBundleID: [:],
            now: date("2026-08-18")
        )

        XCTAssertEqual(snapshot.todayRows.first?.count, 105)
        XCTAssertEqual(snapshot.weekRows.first?.count, 105)
        XCTAssertEqual(snapshot.totalRows.first?.count, 105)
    }

    func testEmptyDataReturnsEmptyRows() {
        let snapshot = StatsAggregator().produceSnapshot(
            counts: .empty,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            now: date("2026-08-18")
        )

        XCTAssertTrue(snapshot.todayRows.isEmpty)
        XCTAssertTrue(snapshot.weekRows.isEmpty)
        XCTAssertTrue(snapshot.totalRows.isEmpty)
    }

    func testZeroCountsExcludedFromRows() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.a": 0, "com.b": 5]

        let snapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            now: date("2026-08-18")
        )

        XCTAssertEqual(snapshot.todayRows.map(\.bundleID), ["com.b"])
    }

    func testEqualCountRowsOrderedStablyByBundleID() {
        var counts = DailyCounts()
        counts.days["2026-08-18"] = ["com.b": 5, "com.a": 5]

        let snapshot = StatsAggregator().produceSnapshot(
            counts: counts,
            sessionDeltaByBundleID: [:],
            metadataByBundleID: [:],
            now: date("2026-08-18")
        )

        XCTAssertEqual(snapshot.todayRows.map(\.bundleID), ["com.a", "com.b"])
    }
}
