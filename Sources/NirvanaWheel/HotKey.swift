import Carbon
import Foundation

/// A system-wide hotkey with separate press and release callbacks (Carbon `RegisterEventHotKey`).
/// Needs no Accessibility permission. The key press is consumed, so other apps don't see it.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private static var registry: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    /// Returns nil when macOS refuses the combination (usually: another app already owns it).
    init?(keyCode: UInt32, carbonModifiers: UInt32) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.installHandler()
        let hkID = EventHotKeyID(signature: OSType(0x4E52_4E47), id: id) // "NRNG"
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.registry[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                guard let h = HotKey.registry[hk.id] else { return }
                pressed ? h.onPress() : h.onRelease()
            }
            return noErr
        }, types.count, &types, nil, nil)
    }
}

enum KeyCodes {
    static let table: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "`": kVK_ANSI_Grave, "tab": kVK_Tab, "return": kVK_Return,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
    ]

    static func carbonModifiers(_ names: [String]) -> UInt32 {
        var m = 0
        for n in names {
            switch n.lowercased() {
            case "command", "cmd": m |= cmdKey
            case "option", "alt", "opt": m |= optionKey
            case "control", "ctrl": m |= controlKey
            case "shift": m |= shiftKey
            default: break
            }
        }
        return UInt32(m)
    }

    static func describe(_ hk: HotkeyConfig) -> String {
        let order: [(String, String)] = [("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘")]
        let mods = Set(hk.modifiers.map { $0.lowercased() })
        let prefix = order.filter { mods.contains($0.0) }.map(\.1).joined()
        return prefix + (hk.key == "space" ? "Space" : hk.key.uppercased())
    }
}
