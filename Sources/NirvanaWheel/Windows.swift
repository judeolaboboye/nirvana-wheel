import AppKit
import ApplicationServices

/// Moves and resizes the front window of the app you're using. Needs the Accessibility permission.
enum WindowAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, nextScreen

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .maximize: return "Fill Screen"
        case .center: return "Centre"
        case .nextScreen: return "Next Display"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .maximize: return "rectangle.fill"
        case .center: return "rectangle.center.inset.filled"
        case .nextScreen: return "rectangle.on.rectangle"
        }
    }

    /// Target frame in AppKit coordinates (bottom-left origin) inside the screen's visible area.
    func target(window: CGRect, in vf: CGRect, next: CGRect?) -> CGRect {
        switch self {
        case .leftHalf: return CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .rightHalf: return CGRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .topHalf: return CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: vf.height / 2)
        case .bottomHalf: return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2)
        case .maximize: return vf
        case .center:
            let w = min(window.width, vf.width), h = min(window.height, vf.height)
            return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        case .nextScreen:
            guard let n = next else { return window }
            // Keep the same relative place and size on the other display.
            let rx = (window.minX - vf.minX) / vf.width, ry = (window.minY - vf.minY) / vf.height
            let rw = window.width / vf.width, rh = window.height / vf.height
            return CGRect(x: n.minX + rx * n.width, y: n.minY + ry * n.height, width: rw * n.width, height: rh * n.height)
        }
    }
}

enum WindowMover {
    /// True when Accessibility is allowed. With `prompt`, macOS shows its "allow" dialog the first time.
    @discardableResult
    static func trusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func perform(_ action: WindowAction, onError: @escaping (String) -> Void) {
        guard trusted(prompt: true) else {
            onError("To move windows, allow Nirvana Wheel in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let win = value else { return onError("\(app.localizedName ?? "That app") has no window to move.") }
        let window = win as! AXUIElement

        guard let topLeftFrame = frame(of: window) else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        // AX uses top-left origin; convert to AppKit's bottom-left.
        let current = CGRect(x: topLeftFrame.minX, y: primaryH - topLeftFrame.maxY, width: topLeftFrame.width, height: topLeftFrame.height)
        let screens = NSScreen.screens
        let idx = screens.firstIndex { $0.frame.contains(CGPoint(x: current.midX, y: current.midY)) } ?? 0
        let vf = screens[idx].visibleFrame
        let next = screens.count > 1 ? screens[(idx + 1) % screens.count].visibleFrame : nil
        let t = action.target(window: current, in: vf, next: next)
        set(window, CGRect(x: t.minX, y: primaryH - t.maxY, width: t.width, height: t.height))
    }

    private static func frame(of w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private static func set(_ w: AXUIElement, _ r: CGRect) {
        var pos = r.origin, size = r.size
        // Size, then position, then size again: some apps clamp size to the screen they're on.
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
    }
}
