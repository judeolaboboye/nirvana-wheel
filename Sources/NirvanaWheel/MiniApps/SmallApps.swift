import AppKit
import CoreImage.CIFilterBuiltins
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Timer

final class TimerStore: ObservableObject {
    static let shared = TimerStore()
    @Published var endsAt: Date?
    @Published var total: TimeInterval = 0
    @Published var now = Date()
    @Published var finished = false
    private var tick: Timer?

    var remaining: TimeInterval { max(0, (endsAt ?? now).timeIntervalSince(now)) }

    func start(minutes: Double) {
        total = minutes * 60
        endsAt = Date().addingTimeInterval(total)
        finished = false
        tick?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    func stop() { tick?.invalidate(); tick = nil; endsAt = nil; finished = false }

    private func update() {
        now = Date()
        if let e = endsAt, now >= e {
            tick?.invalidate(); tick = nil
            endsAt = nil
            finished = true
            NSSound(named: "Glass")?.play()
            MiniAppHost.shared.open(.timer)
            NSApp.requestUserAttention(.criticalRequest)
        }
    }
}

struct TimerView: View {
    @ObservedObject private var t = TimerStore.shared
    @State private var custom = ""

    var body: some View {
        MiniCard {
            if t.finished {
                Text("Time's up").font(.system(size: 30, weight: .bold)).foregroundStyle(ringAccent)
                Button("OK") { t.stop() }.keyboardShortcut(.defaultAction)
            } else if t.endsAt != nil {
                Text(format(t.remaining)).font(.system(size: 44, weight: .bold, design: .monospaced))
                ProgressView(value: t.total == 0 ? 0 : 1 - t.remaining / t.total).tint(ringAccent)
                Button("Stop") { t.stop() }
            } else {
                Text("Start a timer").font(.headline)
                HStack {
                    ForEach([1.0, 5, 10, 25, 45], id: \.self) { m in
                        Button("\(Int(m))m") { t.start(minutes: m) }
                    }
                }
                HStack {
                    TextField("Minutes", text: $custom).textFieldStyle(.roundedBorder).frame(width: 90)
                        .onSubmit(startCustom)
                    Button("Start", action: startCustom)
                }
            }
        }
    }

    private func startCustom() {
        if let m = Double(custom.replacingOccurrences(of: ",", with: ".")), m > 0 { t.start(minutes: m) }
    }

    private func format(_ s: TimeInterval) -> String {
        let n = Int(s.rounded(.up))
        return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60)
                         : String(format: "%02d:%02d", n / 60, n % 60)
    }
}

// MARK: - Scratchpad

struct ScratchpadView: View {
    private static let file = appDataURL("scratchpad.txt")
    @State private var text = (try? String(contentsOf: ScratchpadView.file, encoding: .utf8)) ?? ""

    var body: some View {
        MiniCard {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .onChange(of: text) { _, new in try? new.write(to: Self.file, atomically: true, encoding: .utf8) }
            HStack {
                Text("Saved as you type").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Copy all") { copyToClipboard(text) }.controlSize(.small)
            }
        }
    }
}

// MARK: - Colour picker

struct ColorPickerView: View {
    @State private var colors: [NSColor] = []
    @State private var copied = ""

    var body: some View {
        MiniCard {
            Button {
                NSColorSampler().show { c in
                    guard let c = c?.usingColorSpace(.sRGB) else { return }
                    colors.insert(c, at: 0)
                    copyToClipboard(hex(c)); copied = hex(c)
                }
            } label: { Label("Pick a colour from the screen", systemImage: "eyedropper") }
            .controlSize(.large)
            if !copied.isEmpty { Text("Copied \(copied)").font(.caption).foregroundStyle(ringAccent) }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(colors.prefix(12).enumerated()), id: \.offset) { _, c in
                        HStack {
                            RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: c)).frame(width: 34, height: 22)
                            Button(hex(c)) { copyToClipboard(hex(c)); copied = hex(c) }.buttonStyle(.plain).monospaced()
                            Spacer()
                            Button(rgb(c)) { copyToClipboard(rgb(c)); copied = rgb(c) }.buttonStyle(.plain)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func hex(_ c: NSColor) -> String {
        String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
    private func rgb(_ c: NSColor) -> String {
        "rgb(\(Int(c.redComponent * 255)), \(Int(c.greenComponent * 255)), \(Int(c.blueComponent * 255)))"
    }
}

// MARK: - QR code maker

enum QR {
    static func image(for text: String, scale: CGFloat = 10) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static func decode(_ cg: CGImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: CIImage(cgImage: cg)) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}

struct QRMakerView: View {
    @State private var text = NSPasteboard.general.string(forType: .string) ?? ""

    var body: some View {
        MiniCard {
            TextField("Text or link", text: $text).textFieldStyle(.roundedBorder)
            if let img = text.isEmpty ? nil : QR.image(for: text) {
                Image(nsImage: img).interpolation(.none).resizable().scaledToFit()
                    .padding(8).background(Color.white).cornerRadius(8)
                    .frame(maxWidth: .infinity)
                    .onDrag { NSItemProvider(object: img) }
                Button("Copy image") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img])
                }.controlSize(.small)
            } else {
                Spacer()
            }
        }
    }
}

// MARK: - QR scanner (from a part of the screen)

struct QRScannerView: View {
    @State private var results: [String] = []
    @State private var status = "Drag over a QR code on screen."

    var body: some View {
        MiniCard {
            Button { scan() } label: { Label("Scan part of the screen", systemImage: "viewfinder") }.controlSize(.large)
            Text(status).font(.caption).foregroundStyle(.secondary)
            ForEach(results, id: \.self) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r).textSelection(.enabled).lineLimit(4)
                    HStack {
                        Button("Copy") { copyToClipboard(r) }
                        if let u = URL(string: r), u.scheme?.hasPrefix("http") == true {
                            Button("Open") { NSWorkspace.shared.open(u) }
                        }
                    }.controlSize(.small)
                }
                .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)
            }
            Spacer()
        }
    }

    private func scan() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("nr-qr-\(UUID().uuidString).png")
        NSApp.keyWindow?.orderOut(nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", path.path]
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                MiniAppHost.shared.open(.qrScanner)
                defer { try? FileManager.default.removeItem(at: path) }
                guard let img = NSImage(contentsOf: path),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    status = "Nothing captured."; return
                }
                results = QR.decode(cg)
                status = results.isEmpty ? "No QR code found in that area." : "Found \(results.count)."
            }
        }
        try? p.run()
    }
}

// MARK: - Stay awake (caffeine)

final class CaffeineStore: ObservableObject {
    static let shared = CaffeineStore()
    @Published private(set) var until: Date?
    @Published private(set) var on = false
    private var assertion: IOPMAssertionID = 0
    private var offTimer: Timer?

    func enable(minutes: Double?) {
        disable()
        var id: IOPMAssertionID = 0
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "Nirvana Wheel: Stay Awake" as CFString, &id)
        guard ok == kIOReturnSuccess else { return }
        assertion = id
        on = true
        if let m = minutes {
            until = Date().addingTimeInterval(m * 60)
            let t = Timer(timeInterval: m * 60, repeats: false) { [weak self] _ in self?.disable() }
            RunLoop.main.add(t, forMode: .common)
            offTimer = t
        }
    }

    func disable() {
        offTimer?.invalidate(); offTimer = nil
        if on { IOPMAssertionRelease(assertion) }
        on = false; until = nil
    }
}

struct CaffeineView: View {
    @ObservedObject private var c = CaffeineStore.shared
    var body: some View {
        MiniCard {
            HStack {
                Image(systemName: c.on ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 30)).foregroundStyle(c.on ? ringAccent : .secondary)
                VStack(alignment: .leading) {
                    Text(c.on ? "Your Mac is staying awake" : "Normal sleep").font(.headline)
                    if let u = c.until { Text("until \(u.formatted(date: .omitted, time: .shortened))").font(.caption) }
                    else if c.on { Text("until you turn it off").font(.caption) }
                }
            }
            HStack {
                Button("30 min") { c.enable(minutes: 30) }
                Button("1 hour") { c.enable(minutes: 60) }
                Button("3 hours") { c.enable(minutes: 180) }
                Button("Always") { c.enable(minutes: nil) }
            }
            if c.on { Button("Turn off") { c.disable() } }
        }
    }
}
