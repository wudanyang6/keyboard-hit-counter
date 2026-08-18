import XCTest
import CAtomic

final class CAtomicTests: XCTestCase {
    func testCreateIncrementLoad() {
        let c = khc_counters_create(4)
        XCTAssertNotNil(c, "create 不应返回 nil")
        defer { khc_counters_destroy(c) }

        XCTAssertEqual(khc_counters_capacity(c), 4)
        XCTAssertEqual(khc_counters_current_slot(c), 0)

        khc_counters_set_current_slot(c, 1)
        XCTAssertEqual(khc_counters_current_slot(c), 1)

        XCTAssertEqual(khc_counters_increment_current(c), 1)
        XCTAssertEqual(khc_counters_increment_current(c), 2)
        XCTAssertEqual(khc_counters_load(c, 1), 2)
        XCTAssertEqual(khc_counters_load(c, 0), 0)
    }

    func testInvalidSlotLoadReturnsZero() {
        let c = khc_counters_create(2)
        defer { khc_counters_destroy(c) }
        XCTAssertEqual(khc_counters_load(c, -1), 0)
        XCTAssertEqual(khc_counters_load(c, 5), 0)
    }
}