import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

// MARK: - Mirror (camera preview)

final class CameraPreview: NSView {
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    var onStatus: (String?) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else { self.onStatus("denied"); return }
                self.configure()
            }
        }
    }

    private func configure() {
        guard preview == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            onStatus("No camera found."); return
        }
        session.addInput(input)
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        p.frame = bounds
        p.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // Mirror like a real mirror.
        if let c = p.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
        layer?.addSublayer(p)
        preview = p
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        onStatus(nil)
    }

    func stop() { DispatchQueue.global().async { self.session.stopRunning() } }
}

struct CameraPreviewRep: NSViewRepresentable {
    @Binding var status: String?
    func makeNSView(context: Context) -> CameraPreview {
        let v = CameraPreview()
        v.onStatus = { s in status = s }
        v.start()
        return v
    }
    func updateNSView(_ v: CameraPreview, context: Context) {}
    static func dismantleNSView(_ v: CameraPreview, coordinator: ()) { v.stop() }
}

struct MirrorView: View {
    @State private var status: String? = "Starting camera…"
    var body: some View {
        ZStack {
            CameraPreviewRep(status: $status)
            if status == "denied" {
                PermissionNote(text: "Mirror needs your camera. macOS hasn't allowed it yet.", pane: .camera)
                    .background(Color.black.opacity(0.85))
            } else if let s = status {
                Text(s).padding().multilineTextAlignment(.center)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mic check (live level)

final class MicLevel: ObservableObject {
    @Published var level: Float = 0   // 0...1
    @Published var peak: Float = 0
    @Published var status: String?
    private let engine = AVAudioEngine()
    private var running = false

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { self.status = "denied"; return }
                self.run()
            }
        }
    }

    private func run() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { status = "No microphone found."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            let db = 20 * log10(max(rms, 0.000_01))           // -100...0
            let v = max(0, min(1, (db + 60) / 60))             // show the top 60 dB
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = self.level * 0.6 + v * 0.4
                self.peak = max(v, self.peak - 0.01)
            }
        }
        do { try engine.start(); running = true; status = nil }
        catch { status = "Couldn't start the microphone: \(error.localizedDescription)" }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

struct MicCheckView: View {
    @StateObject private var mic = MicLevel()
    var body: some View {
        if mic.status == "denied" {
            PermissionNote(text: "Mic Check needs your microphone. macOS hasn't allowed it yet.", pane: .microphone)
                .padding(.top, 20)
        } else {
            meter
        }
    }

    private var meter: some View {
        MiniCard {
            Text(AudioDevices.defaultName(input: true) ?? "Microphone").font(.headline)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [.green, ringAccent, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(mic.level))
                    Rectangle().fill(Color.white).frame(width: 2).offset(x: g.size.width * CGFloat(mic.peak))
                }
            }
            .frame(height: 22)
            Text(mic.status ?? (mic.level > 0.85 ? "Too loud: may clip" : mic.level < 0.2 ? "Quiet: speak up or move closer" : "Good level"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .onAppear { mic.start() }
        .onDisappear { mic.stop() }
    }
}

// MARK: - Sound output switcher + volume (CoreAudio)

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum AudioDevices {
    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    static func all(input: Bool) -> [AudioDevice] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { channels($0, input: input) > 0 }.compactMap { id in name(id).map { AudioDevice(id: id, name: $0) } }
    }

    private static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func name(_ id: AudioDeviceID) -> String? {
        var a = addr(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func defaultName(input: Bool) -> String? { defaultDevice(input: input).flatMap(name) }

    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var v = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
    }

    /// Output volume 0...1, using the main element or, failing that, channels 1 and 2.
    static func volume(_ id: AudioDeviceID) -> Float? {
        for el: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var a = addr(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, el)
            guard AudioObjectHasProperty(id, &a) else { continue }
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    static func setVolume(_ id: AudioDeviceID, _ value: Float) {
        var v = Float32(max(0, min(1, value)))
        var a = addr(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(id, &a) {
            AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v); return
        }
        for el: UInt32 in [1, 2] {
            var c = addr(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, el)
            if AudioObjectHasProperty(id, &c) { AudioObjectSetPropertyData(id, &c, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) }
        }
    }
}

struct AudioView: View {
    @State private var outputs: [AudioDevice] = []
    @State private var inputs: [AudioDevice] = []
    @State private var current: AudioDeviceID?
    @State private var currentIn: AudioDeviceID?
    @State private var volume: Float = 0.5
    @State private var hasVolume = false
    @State private var showInputs = false

    var body: some View {
        MiniCard {
            Text("Output").font(.headline)
            ForEach(outputs) { d in row(d, selected: d.id == current) { AudioDevices.setDefault(d.id, input: false); refresh() } }
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: Binding(get: { volume }, set: { v in volume = v; if let c = current { AudioDevices.setVolume(c, v) } }))
                    .disabled(!hasVolume).tint(ringAccent)
                Image(systemName: "speaker.wave.3.fill")
            }
            if !hasVolume { Text("This device sets its own volume.").font(.caption).foregroundStyle(.tertiary) }
            Toggle("Show inputs", isOn: $showInputs).toggleStyle(.switch).controlSize(.small)
            if showInputs {
                Text("Input").font(.headline)
                ForEach(inputs) { d in row(d, selected: d.id == currentIn) { AudioDevices.setDefault(d.id, input: true); refresh() } }
            }
            Spacer()
        }
        .onAppear(perform: refresh)
    }

    private func row(_ d: AudioDevice, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? ringAccent : .secondary)
                Text(d.name)
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func refresh() {
        outputs = AudioDevices.all(input: false)
        inputs = AudioDevices.all(input: true)
        current = AudioDevices.defaultDevice(input: false)
        currentIn = AudioDevices.defaultDevice(input: true)
        if let c = current, let v = AudioDevices.volume(c) { volume = v; hasVolume = true } else { hasVolume = false }
    }
}
