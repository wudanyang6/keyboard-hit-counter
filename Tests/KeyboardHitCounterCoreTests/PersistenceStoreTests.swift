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