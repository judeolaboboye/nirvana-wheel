import CoreGraphics
import Foundation

/// Pure maths for the ring: which item the pointer is on. No UI, so it is easy to test.
struct WheelGeometry {
    /// Pointer closer than this to the centre selects nothing (release = cancel).
    var deadZone: CGFloat = 40
    /// Inner and outer edge of the drawn ring.
    var innerRadius: CGFloat = 52
    var outerRadius: CGFloat = 136
    /// Pointer further out than this, on a sub-menu item, opens that sub-menu.
    var pushRadius: CGFloat = 150

    /// Angle of a point measured from 12 o'clock, going clockwise, in radians (0..<2π).
    /// `dx`, `dy` use maths axes: x to the right, y up (AppKit screen coordinates).
    static func clockAngle(dx: CGFloat, dy: CGFloat) -> CGFloat {
        var a = atan2(dx, dy)
        if a < 0 { a += 2 * .pi }
        return a
    }

    /// Index of the item under the pointer, or nil inside the dead zone or when there are no items.
    func index(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0, hypot(dx, dy) >= deadZone else { return nil }
        let slice = 2 * .pi / CGFloat(count)
        // Item 0 is centred on 12 o'clock, so shift by half a slice.
        var a = Self.clockAngle(dx: dx, dy: dy) + slice / 2
        if a >= 2 * .pi { a -= 2 * .pi }
        return min(Int(a / slice), count - 1)
    }

    /// Centre angle (from 12 o'clock, clockwise) of item `i`.
    static func centreAngle(of i: Int, count: Int) -> CGFloat {
        2 * .pi / CGFloat(count) * CGFloat(i)
    }
}
