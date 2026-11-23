import AppKit
import IOKit.ps
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shelf

final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var files: [URL] = []
    @Published var catchScreenshots = false { didSet { watchScreenshots() } }
    private var watchTimer: Timer?
    private var seen = Set<String>()
    private let file = appDataURL("shelf.json")

    init() {
        if let data = try? Data(contentsOf: file), let paths = try? JSONDecoder().decode([String].self, from: data) {
            files = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(_ urls: [URL]) {
        for u in urls where !files.contains(u) { files.append(u) }
        save()
    }
    func remove(_ u: URL) { files.removeAll { $0 == u }; save() }
    func clear() { files = []; save() }
    private func save() {
        if let d = try? JSONEncoder().encode(files.map(\.path)) { try? d.write(to: file, options: .atomic) }
    }

    /// What is selected in Finder right now.
    func addFinderSelection() {
        let src = """
        tell application "Finder"
          set out to ""
          repeat with f in (get selection)
            set out to out & POSIX path of (f as alias) & linefeed
          end repeat
          return out
        end tell
        """
        DispatchQueue.global().async {
            var err: NSDictionary?
            let r = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue ?? ""
            let urls = r.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            DispatchQueue.main.async { self.add(urls) }
        }
    }

    static var screenshotFolder: URL {
        let d = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: ((d ?? "~/Desktop") as NSString).expandingTildeInPath)
    }

    private func watchScreenshots() {
        watchTimer?.invalidate(); watchTimer = nil
        guard catchScreenshots else { return }
        seen = Set(listScreenshots().map(\.path))
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let new = self.listScreenshots().filter { !self.seen.contains($0.path) }
            guard !new.isEmpty else { return }
            new.forEach { self.seen.insert($0.path) }
            self.add(new)
            MiniAppHost.shared.open(.shelf)
        }
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    private func listScreenshots() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: Self.screenshotFolder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { ["png", "jpg", "mov"].contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix(".") }
    }
}

struct ShelfView: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var targeted = false

    var body: some View {
        MiniCard {
            HStack {
                Button("Add Finder selection") { shelf.addFinderSelection() }.controlSize(.small)
                Spacer()
                if !shelf.files.isEmpty { Button("Clear") { shelf.clear() }.controlSize(.small) }
            }
            Toggle("Catch new screenshots", isOn: $shelf.catchScreenshots).toggleStyle(.switch).controlSize(.small)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(targeted ? ringAccent : Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                if shelf.files.isEmpty {
                    Text("Drop files here, then drag them out\nwhere you need them.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(shelf.files, id: \.self) { u in
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 28, height: 28)
                                    Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button { shelf.remove(u) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.05)).cornerRadius(6)
                                .onDrag { NSItemProvider(contentsOf: u) ?? NSItemProvider() }
                                .onTapGesture(count: 2) { NSWorkspace.shared.open(u) }
                            }
                        }.padding(6)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { shelf.add([url]) } }
                    }
                }
                return true
            }
        }
    }
}

// MARK: - Focus (dim everything except the front window)

final class FocusController: ObservableObject {
    static let shared = FocusController()
    @Published private(set) var on = false
    @Published var dim: Double = 0.65 { didSet { overlays.forEach { $0.alphaValue = CGFloat(dim) } } }
    private var overlays: [NSWindow] = []
    private var timer: Timer?

    func toggle() { on ? stop() : start() }

    func start() {
        stop()
        for s in NSScreen.screens {
            let w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.alphaValue = CGFloat(dim)
            let v = HoleView(frame: NSRect(origin: .zero, size: s.frame.size))
            w.contentView = v
            w.orderFrontRegardless()
            overlays.append(w)
        }
        on = true
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        update()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        on = false
    }

    /// Finds the front window of the frontmost app (window bounds need no special permission).
    private func update() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let front = list.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        var rect: CGRect?
        if pid != mine, let b = front?[kCGWindowBounds as String] as? NSDictionary { rect = CGRect(dictionaryRepresentation: b) }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        for w in overlays {
            guard let v = w.contentView as? HoleView else { continue }
            if let r = rect {
                // CoreGraphics uses top-left origin; AppKit uses bottom-left.
                let flipped = CGRect(x: r.minX, y: mainH - r.maxY, width: r.width, height: r.height)
                v.hole = flipped.offsetBy(dx: -w.frame.minX, dy: -w.frame.minY)
            } else { v.hole = nil }
        }
    }

    final class HoleView: NSView {
        var hole: CGRect? { didSet { if hole != oldValue { needsDisplay = true } } }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            let p = NSBezierPath(rect: bounds)
            if let h = hole { p.append(NSBezierPath(roundedRect: h.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)); p.windingRule = .evenOdd }
            p.fill()
        }
    }
}

struct FocusView: View {
    @ObservedObject private var f = FocusController.shared
    var body: some View {
        MiniCard {
            Text("Dims everything except the window you're working in.").font(.callout).foregroundStyle(.secondary)
            Button(f.on ? "Turn Focus off" : "Turn Focus on") { f.toggle() }.controlSize(.large)
            HStack { Text("Dim"); Slider(value: $f.dim, in: 0.2...0.9).tint(ringAccent) }
            Spacer()
        }
    }
}

// MARK: - Magnifier (needs Screen Recording permission)

final class MagnifierModel: ObservableObject {
    @Published var image: CGImage?
    @Published var status: String?
    @Published var zoom: Double = 3
    private var timer: Timer?
    private var display: SCDisplay?
    private var busy = false

    @Published var needsPermission = false

    func start() {
        // Screen Recording: ask macOS once; it only takes effect after the app is reopened.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            needsPermission = true
            return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                guard let content else {
                    self.status = "Allow Screen Recording for Nirvana Wheel in System Settings → Privacy & Security, then reopen this."
                    _ = error; return
                }
                self.display = content.displays.first
                let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.grab() }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func grab() {
        guard !busy, let display else { return }
        busy = true
        let m = NSEvent.mouseLocation
        let h = NSScreen.screens.first?.frame.height ?? 0
        let side = 300 / zoom
        let rect = CGRect(x: m.x - side / 2, y: (h - m.y) - side / 2, width: side, height: side)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = rect
        cfg.width = 300; cfg.height = 300
        cfg.showsCursor = false
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, _ in
            DispatchQueue.main.async { self.image = img; self.busy = false }
        }
    }
}

struct MagnifierView: View {
    @StateObject private var m = MagnifierModel()
    var body: some View {
        if m.needsPermission {
            VStack(spacing: 8) {
                PermissionNote(text: "Magnifier needs Screen Recording. macOS hasn't allowed it yet.", pane: .screen)
                Button("Reopen Nirvana Wheel after allowing it") { relaunch() }.controlSize(.small).padding(.bottom, 10)
            }
            .padding(.top, 20)
            .onAppear { m.start() }
        } else {
            lens
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(url.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    private var lens: some View {
        VStack(spacing: 6) {
            ZStack {
                if let img = m.image {
                    Image(decorative: img, scale: 1).interpolation(.none).resizable().scaledToFill()
                } else {
                    Text(m.status ?? "Starting…").padding().multilineTextAlignment(.center)
                }
                Image(systemName: "plus").foregroundStyle(ringAccent.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack { Text("Zoom"); Slider(value: $m.zoom, in: 1.5...8).tint(ringAccent) }.padding(.horizontal, 10).padding(.bottom, 8)
        }
        .padding(.top, 26)
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }
}

// MARK: - System glance

final class SystemStats: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memUsed: Double = 0
    @Published var memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var battery: (percent: Int, charging: Bool)?
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    private var timer: Timer?
    private var prevTicks: (used: UInt64, total: UInt64)?

    func start() {
        update()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func update() {
        // CPU, from the change in total ticks since last time.
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if ok == KERN_SUCCESS {
            let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
            let used = user + sys + nice, total = used + idle
            if let p = prevTicks, total > p.total { cpu = Double(used - p.used) / Double(total - p.total) }
            prevTicks = (used, total)
        }
        // Memory in use (active + wired + compressed), like Activity Monitor's "Memory Used".
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmOK = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmOK == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            memUsed = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        }
        // Battery.
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let d = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
           let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
            battery = (cap * 100 / max, (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        // Disk.
        let root = URL(fileURLWithPath: "/")
        if let v = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
    }
}

struct SystemGlanceView: View {
    @StateObject private var s = SystemStats()
    var body: some View {
        MiniCard {
            gauge("CPU", s.cpu, String(format: "%.0f%%", s.cpu * 100))
            gauge("Memory", s.memUsed / s.memTotal, "\(gb(s.memUsed)) of \(gb(s.memTotal))")
            if s.diskTotal > 0 {
                gauge("Disk used", 1 - Double(s.diskFree) / Double(s.diskTotal), "\(gb(Double(s.diskFree))) free")
            }
            if let b = s.battery {
                gauge(b.charging ? "Battery (charging)" : "Battery", Double(b.percent) / 100, "\(b.percent)%")
            }
            Spacer()
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }

    private func gauge(_ title: String, _ v: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title).font(.caption.bold()); Spacer(); Text(label).font(.caption).monospacedDigit() }
            ProgressView(value: min(max(v, 0), 1)).tint(v > 0.85 ? .red : ringAccent)
        }
    }

    private func gb(_ bytes: Double) -> String { String(format: "%.1f GB", bytes / 1_073_741_824) }
}
