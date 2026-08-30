import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class AppMetadataStoreTests: XCTestCase {
    func testRoundTripPersistsMetadata() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AppMetadataStore(fileURL: url)
        store.record(
            AppMetadata(displayName: "Xcode", iconData: Data([0x01, 0x02])),
            forBundleID: "com.apple.dt.Xcode"
        )
        try store.save()

        let reloaded = AppMetadataStore(fileURL: url)
        XCTAssertEqual(reloaded.metadata(forBundleID: "com.apple.dt.Xcode")?.displayName, "Xcode")
        XCTAssertEqual(reloaded.metadata(forBundleID: "com.apple.dt.Xcode")?.iconData, Data([0x01, 0x02]))
    }

    func testLoadMissingFileReturnsEmpty() {
        let url = temporaryFileURL()
        let store = AppMetadataStore(fileURL: url)
        XCTAssertEqual(store.snapshot(), [:])
    }

    func testSaveWithoutRecordDoesNotWriteFile() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppMetadataStore(fileURL: url)
        try store.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInMemoryStoreDoesNotPersist() throws {
        let store = AppMetadataStore()
        store.record(AppMetadata(displayName: "A", iconData: nil), forBundleID: "com.a")
        try store.save()
        XCTAssertEqual(store.metadata(forBundleID: "com.a")?.displayName, "A")
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("khc-test-\(UUID().uuidString)")
            .appendingPathComponent("metadata.json")
    }
}
