import AppKit
import XCTest
@testable import NirvanaWheel

/// Drives the wheel in click mode with fake pointer positions (no mouse needed).
final class ClickModeTests: XCTestCase {
    @MainActor func testClickIntoSubMenuThenClickMiddleGoesBack() throws {
        _ = NSApplication.shared
        let ring = RingController()
        let items = RingConfig.default.items
        let tools = try XCTUnwrap(items.firstIndex { $0.title == "Tools" })
        ring.open(items: items, sticky: true)
        defer { ring.close() }
        let c = ring.centre
        // Point at "Tools" (centre angle of its slice, 100 pt out) and click: the Tools ring opens.
        let a = WheelGeometry.centreAngle(of: tools, count: items.count)
        ring.release(pointer: CGPoint(x: c.x + 100 * sin(a), y: c.y + 100 * cos(a)))
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.model.parentTitle, "Tools")
        XCTAssertEqual(ring.model.items.count, MiniAppID.allCases.count)
        // Click the middle: back to the main wheel, still open.
        ring.release(pointer: c)
        XCTAssertTrue(ring.isOpen)
        XCTAssertNil(ring.model.parentTitle)
        XCTAssertEqual(ring.model.items.map(\.title), items.map(\.title))
        // Click the middle again on the main wheel: it closes.
        ring.release(pointer: c)
        XCTAssertFalse(ring.isOpen)
    }
}
