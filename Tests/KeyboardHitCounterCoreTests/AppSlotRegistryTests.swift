import XCTest
import Foundation
@testable import KeyboardHitCounterCore

final class AppSlotRegistryTests: XCTestCase {
    func testSameBundleIDReturnsSameSlot() {
        let registry = AppSlotRegistry()
        let a = registry.slot(forBundleID: "com.apple.Safari")
        let b = registry.slot(forBundleID: "com.apple.Safari")
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a, 0)
    }

    func testSlotZeroMapsToNil() {
        let registry = AppSlotRegistry()
        XCTAssertNil(registry.bundleID(forSlot: 0))
    }

    func testMetadataRoundTrip() {
        let store = AppMetadataStore()
        let metadata = AppMetadata(displayName: "Safari", iconData: Data([0x01, 0x02]))
        store.record(metadata, forBundleID: "com.apple.Safari")
        XCTAssertEqual(store.metadata(forBundleID: "com.apple.Safari")?.displayName, "Safari")
    }
}