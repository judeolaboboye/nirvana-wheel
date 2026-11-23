import AppKit

/// Opens the ring with an extra mouse button: hold it, point, release.
/// Uses a global mouse monitor (no special permission). The click itself still reaches the app underneath,
/// so a side button (3 or 4) works best.
final class MouseTrigger {
    private var monitors: [Any] = []
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    func start(button: Int) {
        stop()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown, handler: { [weak self] e in
            if e.buttonNumber == button { self?.onPress() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp, handler: { [weak self] e in
            if e.buttonNumber == button { self?.onRelease() }
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}

/// Four-finger tap and hold on the trackpad.
///
/// Reads the trackpad through Apple's private MultitouchSupport framework, loaded at run time with `dlopen`, so the
/// app still works (without the gesture) if Apple ever changes it. Only the number of fingers is used.
/// Because the fingers are on the trackpad, the pointer can't move during the hold: the gesture opens the ring in
/// "click to choose" mode instead (move the pointer, click an item; Esc or a click in the middle cancels).
final class TrackpadTrigger {
    static let shared = TrackpadTrigger()
    var onGesture: () -> Void = {}
    private(set) var available = false
    private var started = false
    private var devices: [UnsafeMutableRawPointer] = []
    var deviceCount: Int { devices.count }

    private typealias Callback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    // Gesture state, touched only from the trackpad callback thread.
    fileprivate static var fourSince: Double?
    fileprivate static var fired = false
    fileprivate static var maxFingers: Int32 = 0

    private var stopFn: Stop?
    private var unregisterFn: Register?

    func start() {
        guard !started else { return }
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let c = dlsym(h, "MTDeviceCreateList"), let r = dlsym(h, "MTRegisterContactFrameCallback"),
              let s = dlsym(h, "MTDeviceStart") else { available = false; return }
        let create = unsafeBitCast(c, to: CreateList.self)
        let register = unsafeBitCast(r, to: Register.self)
        let startFn = unsafeBitCast(s, to: Start.self)
        stopFn = dlsym(h, "MTDeviceStop").map { unsafeBitCast($0, to: Stop.self) }
        unregisterFn = dlsym(h, "MTUnregisterContactFrameCallback").map { unsafeBitCast($0, to: Register.self) }

        guard let list = create()?.takeRetainedValue() as NSArray? else { available = false; return }
        for d in list {
            let ptr = Unmanaged.passUnretained(d as AnyObject).toOpaque()
            register(ptr, TrackpadTrigger.frame)
            startFn(ptr, 0)
            devices.append(ptr)
        }
        available = !devices.isEmpty
        started = available
    }

    func stop() {
        guard started else { return }
        for d in devices {
            unregisterFn?(d, TrackpadTrigger.frame)
            stopFn?(d)
        }
        devices = []
        started = false
    }

    /// Called for every trackpad frame. Fires once when exactly four fingers have rested for 0.35 s.
    private static let frame: Callback = { _, _, fingers, timestamp, _ in
        if fingers == 4 {
            if fourSince == nil { fourSince = timestamp }
            if !fired, let t0 = fourSince, timestamp - t0 >= 0.35, maxFingers <= 4 {
                fired = true
                DispatchQueue.main.async { TrackpadTrigger.shared.onGesture() }
            }
        } else {
            fourSince = nil
        }
        maxFingers = max(maxFingers, fingers)
        if fingers == 0 { fired = false; maxFingers = 0 }
        return 0
    }
}
