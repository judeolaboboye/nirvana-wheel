import AppKit
import SwiftUI

/// Shows the ring under the pointer, follows the pointer while the hotkey is held, runs the item on release.
final class RingController {
    let model = RingModel()
    private let panel: NSPanel
    private(set) var centre = CGPoint.zero
    private var timer: Timer?
    private(set) var isOpen = false
    /// Click-to-choose mode (used by the trackpad gesture): the ring stays open until a click or Esc.
    private(set) var sticky = false
    private var catcher: ClickCatcher?
    var onError: (String) -> Void = { _ in }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: RingView.size, height: RingView.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: RingView(model: model))
    }

    /// Top-level items, and the sub-menus opened so far (title + items).
    private var root: [RingItem] = []
    private var stack: [(title: String, items: [RingItem])] = []

    func setItems(_ items: [RingItem]) { root = items; resetLevels() }

    /// Opens with a given ring's items.
    func open(items: [RingItem], sticky: Bool = false) {
        guard !isOpen else { return }
        root = items
        self.sticky = sticky
        open()
        // Catch clicks in both modes: in key mode a click on an item runs it too (instead of reaching the app behind).
        showCatcher(takeFocus: sticky)
    }

    private func showCatcher(takeFocus: Bool) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let c = ClickCatcher(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        c.isOpaque = false
        // Nearly invisible. A fully see-through window lets clicks fall through to the app behind,
        // so keep a faint tint and tell macOS explicitly that this window takes the mouse.
        c.backgroundColor = NSColor(white: 0, alpha: 0.18) // light dim: the screen is "taken" until you choose
        c.ignoresMouseEvents = false
        c.acceptsMouseMovedEvents = true
        let v = CatcherView(frame: NSRect(origin: .zero, size: frame.size))
        v.onClick = { [weak c] in c?.onClick() }
        v.onCancel = { [weak c] in c?.onCancel() }
        c.contentView = v
        c.level = .popUpMenu
        c.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        c.onClick = { [weak self] in self?.release() }
        c.onCancel = { [weak self] in self?.close() }
        if takeFocus {
            NSApp.activate(ignoringOtherApps: true) // so Esc reaches it
            c.makeKeyAndOrderFront(nil)
        } else {
            c.orderFrontRegardless() // key mode: don't steal focus from the app you're in
        }
        panel.orderFrontRegardless()
        catcher = c
    }

    private func resetLevels() {
        stack = []
        model.items = root
        model.parentTitle = nil
    }

    private func push(_ item: RingItem) {
        stack.append((item.title, item.items ?? []))
        model.items = item.items ?? []
        model.parentTitle = item.title
        model.selected = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func pop() {
        stack.removeLast()
        model.items = stack.last?.items ?? root
        model.parentTitle = stack.last?.title
        model.selected = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func open() {
        guard !isOpen else { return } // key auto-repeat sends more presses
        isOpen = true
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let half = RingView.size / 2
        var c = mouse
        if let vf = screen?.visibleFrame { // keep the whole ring on screen
            c.x = min(max(c.x, vf.minX + half), vf.maxX - half)
            c.y = min(max(c.y, vf.minY + half), vf.maxY - half)
        }
        centre = c
        panel.setFrame(NSRect(x: c.x - half, y: c.y - half, width: RingView.size, height: RingView.size), display: false)
        resetLevels()
        model.selected = nil
        panel.orderFrontRegardless()
        model.visible = true
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Hotkey released: run the highlighted item (if any) and hide.
    /// `pointer` is only passed by tests; the app reads the real pointer.
    func release(pointer: CGPoint? = nil) {
        guard isOpen else { return }
        track(pointer)
        let pick = model.selected
        // In click mode, clicking a sub-menu opens it instead of closing,
        // and clicking the middle inside a sub-menu goes back one level.
        if sticky, let i = pick, i < model.items.count, model.items[i].isMenu {
            push(model.items[i]); return
        }
        if sticky, pick == nil, !stack.isEmpty { pop(); return }
        close()
        if let i = pick, i < model.items.count, let action = model.items[i].action {
            ActionRunner.run(action, onError: onError) // a sub-menu released unopened does nothing
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        sticky = false
        catcher?.orderOut(nil); catcher = nil
        timer?.invalidate(); timer = nil
        model.visible = false
        model.selected = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
        }
    }

    func track(_ pointer: CGPoint? = nil) {
        let m = pointer ?? NSEvent.mouseLocation
        let dx = m.x - centre.x, dy = m.y - centre.y
        let dist = hypot(dx, dy)
        let g = model.geometry
        if !stack.isEmpty && dist < g.deadZone && !sticky { pop(); return } // back to the centre = go back
        var idx = g.index(dx: dx, dy: dy, count: model.items.count)
        if let i = idx, model.items[i].isMenu, dist > g.pushRadius, !sticky {   // pushed out past a sub-menu = open it
            push(model.items[i])
            idx = g.index(dx: dx, dy: dy, count: model.items.count)
        }
        if idx != model.selected {
            model.selected = idx
            if idx != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
    }
}

/// Invisible full-screen window that turns the next click into "choose" and Esc into "cancel".
final class ClickCatcher: NSWindow {
    var onClick: () -> Void = {}
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func otherMouseDown(with event: NSEvent) { onClick() }
    override func rightMouseDown(with event: NSEvent) { onCancel() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } // Esc
    }
}

/// Takes every click on the catcher, including the very first one while another app is in front
/// (normally macOS uses that click only to switch apps and drops it).
final class CatcherView: NSView {
    var onClick: () -> Void = {}
    var onCancel: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func otherMouseDown(with event: NSEvent) { onClick() }
    override func rightMouseDown(with event: NSEvent) { onCancel() }
}
