import Foundation

/// What a ring item does.
struct RingAction: Codable, Equatable {
    enum Kind: String, Codable {
        case app        // value = path to a .app
        case url        // value = a web address or any URL
        case shortcut   // value = name of a macOS Shortcut
        case appleScript // value = AppleScript source
        case system     // value = one of SystemAction raw values
        case miniApp    // value = one of MiniAppID raw values
        case window     // value = one of WindowAction raw values
    }
    var type: Kind
    var value: String
}

struct RingItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// SF Symbol name for the icon.
    var symbol: String
    /// What it runs. Nil for a sub-menu.
    var action: RingAction?
    /// When set, this item is a sub-menu: pushing out past the ring opens these items.
    var items: [RingItem]?

    var isMenu: Bool { !(items ?? []).isEmpty }

    enum CodingKeys: String, CodingKey { case title, symbol, action, items }
    init(title: String, symbol: String, action: RingAction? = nil, items: [RingItem]? = nil) {
        self.title = title; self.symbol = symbol; self.action = action; self.items = items
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "circle"
        action = try c.decodeIfPresent(RingAction.self, forKey: .action)
        items = try c.decodeIfPresent([RingItem].self, forKey: .items)
        if action == nil && !isMenu {
            throw DecodingError.dataCorruptedError(forKey: .action, in: c,
                debugDescription: "\"\(title)\" needs an \"action\" or a list of \"items\"")
        }
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(symbol, forKey: .symbol)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(items, forKey: .items)
    }
}

struct HotkeyConfig: Codable, Equatable {
    /// A key name from `KeyCodes.table`, e.g. "space", "r", "`".
    var key: String
    /// Any of "command", "option", "control", "shift".
    var modifiers: [String]
}

/// One ring with its own hotkey. Several profiles = several rings.
struct RingProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var hotkey: HotkeyConfig
    var items: [RingItem]
    enum CodingKeys: String, CodingKey { case name, hotkey, items }
}

struct RingConfig: Codable, Equatable {
    var profiles: [RingProfile]
    /// Extra mouse button that opens the first ring (3 = back side button, 4 = forward, 2 = middle). Nil = off.
    var mouseButton: Int?
    /// Four-finger tap and hold on the trackpad opens the first ring.
    var trackpadGesture: Bool

    /// The first ring's items (kept for older code and tests).
    var items: [RingItem] { profiles.first?.items ?? [] }

    init(profiles: [RingProfile], mouseButton: Int? = nil, trackpadGesture: Bool = false) {
        self.profiles = profiles; self.mouseButton = mouseButton; self.trackpadGesture = trackpadGesture
    }

    enum CodingKeys: String, CodingKey { case profiles, mouseButton, trackpadGesture, hotkey, items }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let p = try c.decodeIfPresent([RingProfile].self, forKey: .profiles) {
            profiles = p
        } else { // first format: one hotkey + one list of items
            profiles = [RingProfile(name: "Main",
                                    hotkey: try c.decode(HotkeyConfig.self, forKey: .hotkey),
                                    items: try c.decode([RingItem].self, forKey: .items))]
        }
        mouseButton = try c.decodeIfPresent(Int.self, forKey: .mouseButton)
        trackpadGesture = try c.decodeIfPresent(Bool.self, forKey: .trackpadGesture) ?? false
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(profiles, forKey: .profiles)
        try c.encodeIfPresent(mouseButton, forKey: .mouseButton)
        try c.encode(trackpadGesture, forKey: .trackpadGesture)
    }

    static func item(_ title: String, _ symbol: String, _ type: RingAction.Kind, _ value: String) -> RingItem {
        RingItem(title: title, symbol: symbol, action: .init(type: type, value: value))
    }

    static let `default` = RingConfig(profiles: [
        RingProfile(name: "Main", hotkey: HotkeyConfig(key: "space", modifiers: ["control", "option"]), items: [
            item("Finder", "folder", .app, "/System/Library/CoreServices/Finder.app"),
            item("Safari", "safari", .app, "/Applications/Safari.app"),
            item("Terminal", "terminal", .app, "/System/Applications/Utilities/Terminal.app"),
            item("Dark Mode", "circle.lefthalf.filled", .system, SystemAction.toggleDarkMode.rawValue),
            RingItem(title: "Windows", symbol: "macwindow", items: WindowAction.allCases.map {
                item($0.title, $0.symbol, .window, $0.rawValue)
            }),
            RingItem(title: "System", symbol: "power", items: [
                item("Lock Screen", "lock", .system, SystemAction.lockScreen.rawValue),
                item("Sleep Display", "moon", .system, SystemAction.sleepDisplay.rawValue),
                item("Empty Trash", "trash", .system, SystemAction.emptyTrash.rawValue),
                item("Eject All", "eject", .system, SystemAction.ejectAll.rawValue),
                item("Sleep Mac", "powersleep", .system, SystemAction.sleepMac.rawValue),
                item("Mute", "speaker.slash", .system, SystemAction.toggleMute.rawValue),
                item("Mission Control", "rectangle.3.group", .system, SystemAction.missionControl.rawValue),
                item("Show Desktop", "menubar.dock.rectangle", .system, SystemAction.showDesktop.rawValue),
                item("Screenshot", "camera.viewfinder", .app, "/System/Applications/Utilities/Screenshot.app"),
            ]),
            RingItem(title: "Tools", symbol: "square.grid.2x2", items: MiniAppID.allCases.map {
                item($0.title, $0.symbol, .miniApp, $0.rawValue)
            }),
            item("Settings", "gearshape", .app, "/System/Applications/System Settings.app"),
        ]),
    ])
}

/// Reads and writes `~/Library/Application Support/NirvanaWheel/config.json`.
enum ConfigStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NirvanaWheel", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Loads the config, writing the default one first if there is none. A broken file falls back to the default
    /// (the broken file is left in place so nothing the user typed is lost).
    static func load() -> (RingConfig, error: String?) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            save(.default)
            return (.default, nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return (try JSONDecoder().decode(RingConfig.self, from: data), nil)
        } catch {
            return (.default, "config.json could not be read: \(error.localizedDescription)")
        }
    }

    static func save(_ config: RingConfig) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: fileURL, options: .atomic) }
    }
}
