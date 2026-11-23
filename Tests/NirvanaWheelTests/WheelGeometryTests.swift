import XCTest
@testable import NirvanaWheel

final class WheelGeometryTests: XCTestCase {
    let g = WheelGeometry()

    func testDeadZoneSelectsNothing() {
        XCTAssertNil(g.index(dx: 5, dy: 5, count: 8))
    }

    func testNoItems() {
        XCTAssertNil(g.index(dx: 0, dy: 100, count: 0))
    }

    func testCompassPointsWithEightItems() {
        XCTAssertEqual(g.index(dx: 0, dy: 100, count: 8), 0)   // up
        XCTAssertEqual(g.index(dx: 100, dy: 0, count: 8), 2)   // right
        XCTAssertEqual(g.index(dx: 0, dy: -100, count: 8), 4)  // down
        XCTAssertEqual(g.index(dx: -100, dy: 0, count: 8), 6)  // left
    }

    func testItemZeroIsCentredOnTop() {
        // Slightly left of straight up still belongs to item 0, not the last item.
        XCTAssertEqual(g.index(dx: -10, dy: 100, count: 8), 0)
        XCTAssertEqual(g.index(dx: 10, dy: 100, count: 8), 0)
    }

    func testFarOutsideStillSelects() {
        XCTAssertEqual(g.index(dx: 0, dy: 900, count: 4), 0)
    }
}
