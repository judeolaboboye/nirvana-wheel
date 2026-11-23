import AppKit
import SwiftUI

/// Every built-in mini-app the ring can open. The raw value is what goes in the settings file:
/// `{"type": "miniApp", "value": "clipboard"}`.
enum MiniAppID: String, CaseIterable, Codable {
    case clipboard, shelf, timer, calculator, colorPicker, scratchpad, qrMaker, qrScanner
    case mirror, micCheck, audio, caffeine, focus, magnifier, systemGlance

    var title: String {
        switch self {
        case .clipboard: return "Clipboard History"
        case .shelf: return "Shelf"
        case .timer: return "Timer"
        case .calculator: return "Calculator"
        case .colorPicker: return "Colour Picker"
        case .scratchpad: return "Scratchpad"
        case .qrMaker: return "QR Code"
        case .qrScanner: return "QR Scanner"
        case .mirror: return "Mirror"
        case .micCheck: return "Mic Check"
        case .audio: return "Sound"
        case .caffeine: return "Stay Awake"
        case .focus: return "Focus"
        case .magnifier: return "Magnifier"
        case .systemGlance: return "System Glance"
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full"
        case .timer: return "timer"
        case .calculator: return "plus.forwardslash.minus"
        case .colorPicker: return "eyedropper"
        case .scratchpad: return "note.text"
        case .qrMaker: return "qrcode"
        case .qrScanner: return "qrcode.viewfinder"
        case .mirror: return "camera"
        case .micCheck: return "mic"
        case .audio: return "speaker.wave.2"
        case .caffeine: return "cup.and.saucer"
        case .focus: return "scope"
        case .magnifier: return "plus.magnifyingglass"
        case .systemGlance: return "gauge.with.dots.needle.33percent"
        }
    }

    var size: CGSize {
        switch self {
        case .clipboard: return CGSize(width: 380, height: 460)
        case .shelf: return CGSize(width: 320, height: 380)
        case .scratchpad: return CGSize(width: 380, height: 340)
        case .mirror: return CGSize(width: 420, height: 320)
        case .systemGlance: return CGSize(width: 300, height: 260)
        default: return CGSize(width: 300, height: 300)
        }
    }

    @MainActor @ViewBuilder func makeView() -> some View {
        switch self {
        case .clipboard: ClipboardView()
        case .shelf: ShelfView()
        case .timer: TimerView()
        case .calculator: CalculatorView()
        case .colorPicker: ColorPickerView()
        case .scratchpad: ScratchpadView()
        case .qrMaker: QRMakerView()
        case .qrScanner: QRScannerView()
        case .mirror: MirrorView()
        case .micCheck: MicCheckView()
        case .audio: AudioView()
        case .caffeine: CaffeineView()
        case .focus: FocusView()
        case .magnifier: MagnifierView()
        case .systemGlance: SystemGlanceView()
        }
    }
}

/// Opens each mini-app in its own small floating window near the pointer. One window per mini-app.
final class MiniAppHost: NSObject, NSWindowDelegate {
    static let shared = MiniAppHost()
    private var windows: [MiniAppID: NSWindow] = [:]

    /// Safe to call from anywhere (timers, background callbacks): hops to the main thread.
    nonisolated func open(_ id: MiniAppID) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.show(id) } }
    }

    @MainActor func show(_ id: MiniAppID) {
        let window = windows[id] ?? makeWindow(id)
        windows[id] = window
        if !window.isVisible { place(window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor private func makeWindow(_ id: MiniAppID) -> NSWindow {
        let w = NSPanel(contentRect: NSRect(origin: .zero, size: id.size),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        w.title = id.title
        w.titlebarAppearsTransparent = true
        w.isFloatingPanel = true
        w.level = .floating
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.delegate = self
        w.contentView = NSHostingView(rootView: id.makeView()
            .frame(minWidth: 240, minHeight: 160)
            .environment(\.colorScheme, .dark))
        w.appearance = NSAppearance(named: .darkAqua)
        return w
    }

    private func place(_ w: NSWindow) {
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { w.center(); return }
        let s = w.frame.size
        let x = min(max(m.x - s.width / 2, vf.minX + 8), vf.maxX - s.width - 8)
        let y = min(max(m.y - s.height / 2, vf.minY + 8), vf.maxY - s.height - 8)
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Shared look for mini-app content.
struct MiniCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(.horizontal, 14)
            .padding(.top, 30)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

let ringAccent = Color(red: 1.0, green: 0.85, blue: 0.30)

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// Folder for anything the app keeps (history, notes, shelf).
func appDataURL(_ name: String) -> URL {
    let dir = ConfigStore.directory
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

/// Privacy pages in System Settings, for the "Open Settings" buttons when access is missing.
enum PrivacyPane: String {
    case camera = "Privacy_Camera", microphone = "Privacy_Microphone", screen = "Privacy_ScreenCapture"
    func open() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") { NSWorkspace.shared.open(u) }
    }
}

/// Shown inside a tool when macOS hasn't allowed what it needs.
struct PermissionNote: View {
    let text: String
    let pane: PrivacyPane
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(ringAccent)
            Text(text).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { pane.open() }
            Text("Turn Nirvana Wheel on there. If it's already on, turn it off and on again, then reopen this tool.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
