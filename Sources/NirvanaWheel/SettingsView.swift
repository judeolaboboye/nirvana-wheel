import AppKit
import Carbon
import SwiftUI

/// The settings window. Edits a working copy; "Save" applies it (hotkeys, triggers, rings) and writes the file.
struct SettingsView: View {
    @State private var cfg: RingConfig
    @State private var saved: RingConfig
    @State private var profileIndex = 0
    /// Where we are inside the selected ring: indices of the sub-menus opened, from the top.
    @State private var path: [Int] = []
    @State private var itemIndex: Int?
    let onSave: (RingConfig) -> Void

    init(initial: RingConfig, onSave: @escaping (RingConfig) -> Void) {
        _cfg = State(initialValue: initial)
        _saved = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 190, idealWidth: 200, maxWidth: 240)
            ringEditor.frame(minWidth: 520)
        }
        .frame(minWidth: 740, minHeight: 500)
    }

    // MARK: Sidebar: rings + general

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rings").font(.headline).padding(.top, 10)
            List(selection: Binding(get: { profileIndex }, set: { if let v = $0 { profileIndex = v; path = []; itemIndex = nil } })) {
                ForEach(Array(cfg.profiles.enumerated()), id: \.offset) { i, p in
                    VStack(alignment: .leading) {
                        Text(p.name)
                        Text(KeyCodes.describe(p.hotkey)).font(.caption).foregroundStyle(.secondary)
                    }.tag(i)
                }
            }
            .frame(minHeight: 140)
            HStack {
                Button { addProfile() } label: { Image(systemName: "plus") }
                Button { removeProfile() } label: { Image(systemName: "minus") }.disabled(cfg.profiles.count <= 1)
            }.buttonStyle(.borderless)
            Divider()
            Text("Also open the first ring with").font(.headline)
            Picker("Mouse button", selection: $cfg.mouseButton) {
                Text("No mouse button").tag(Int?.none)
                Text("Middle button").tag(Int?.some(2))
                Text("Back side button").tag(Int?.some(3))
                Text("Forward side button").tag(Int?.some(4))
            }.labelsHidden()
            Toggle("Four-finger hold on trackpad", isOn: $cfg.trackpadGesture)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private func addProfile() {
        let used = Set(cfg.profiles.map { $0.hotkey.key })
        let key = ["1", "2", "3", "4", "5", "6", "7", "8", "9"].first { !used.contains($0) } ?? "9"
        cfg.profiles.append(RingProfile(name: "Ring \(cfg.profiles.count + 1)",
                                        hotkey: HotkeyConfig(key: key, modifiers: ["control", "option"]), items: []))
        profileIndex = cfg.profiles.count - 1; path = []; itemIndex = nil
    }

    private func removeProfile() {
        guard cfg.profiles.count > 1 else { return }
        cfg.profiles.remove(at: profileIndex)
        clampSelection()
    }

    private func clampSelection() {
        profileIndex = min(profileIndex, cfg.profiles.count - 1)
        path = []; itemIndex = nil
    }

    // MARK: Ring editor

    private var profile: Binding<RingProfile> {
        Binding(get: { cfg.profiles[min(profileIndex, cfg.profiles.count - 1)] },
                set: { cfg.profiles[min(profileIndex, cfg.profiles.count - 1)] = $0 })
    }

    /// Items at the current sub-menu level.
    private var items: Binding<[RingItem]> {
        Binding(get: { Self.items(in: profile.wrappedValue.items, at: path) },
                set: { profile.wrappedValue.items = Self.setting($0, in: profile.wrappedValue.items, at: path) })
    }

    static func items(in root: [RingItem], at path: [Int]) -> [RingItem] {
        var level = root
        for i in path { guard i < level.count else { return [] }; level = level[i].items ?? [] }
        return level
    }

    static func setting(_ new: [RingItem], in root: [RingItem], at path: [Int]) -> [RingItem] {
        guard let first = path.first, first < root.count else { return new }
        var copy = root
        copy[first].items = setting(new, in: root[first].items ?? [], at: Array(path.dropFirst()))
        return copy
    }

    private var ringEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Ring name", text: profile.name).textFieldStyle(.roundedBorder).frame(width: 180)
                Text("Hold").foregroundStyle(.secondary)
                HotkeyRecorder(hotkey: profile.hotkey)
                Spacer()
            }
            breadcrumbs
            HStack(alignment: .top, spacing: 12) {
                itemList.frame(width: 230)
                if let i = itemIndex, i < items.wrappedValue.count {
                    ItemEditor(item: items[i], openSubMenu: { path.append(i); itemIndex = nil })
                } else {
                    Text(items.wrappedValue.isEmpty ? "This ring is empty. Add an item with +." : "Choose an item to edit it.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Text("Up to 12 items per ring reads best.").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if cfg != saved { Text("Not saved yet").font(.caption).foregroundStyle(ringAccent) }
                Button("Revert") { cfg = saved; clampSelection() }.disabled(cfg == saved)
                Button("Save") { onSave(cfg); saved = cfg }
                    .keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(cfg == saved)
            }
        }
        .padding(12)
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button(profile.wrappedValue.name) { path = []; itemIndex = nil }.buttonStyle(.link)
            ForEach(Array(path.enumerated()), id: \.offset) { depth, _ in
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                let p = Array(path.prefix(depth + 1))
                let title = Self.items(in: profile.wrappedValue.items, at: Array(p.dropLast()))[safe: p.last!]?.title ?? "?"
                Button(title) { path = p; itemIndex = nil }.buttonStyle(.link)
            }
        }
    }

    private var itemList: some View {
        VStack(spacing: 6) {
            List(selection: $itemIndex) {
                ForEach(Array(items.wrappedValue.enumerated()), id: \.offset) { i, it in
                    HStack {
                        Image(systemName: it.symbol).frame(width: 20)
                        Text(it.title)
                        Spacer()
                        if it.isMenu { Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption) }
                    }
                    .tag(i)
                    .onTapGesture(count: 2) { if it.isMenu { path.append(i); itemIndex = nil } }
                }
            }
            HStack {
                Menu {
                    Button("Item") { add(RingItem(title: "New Item", symbol: "star", action: .init(type: .app, value: ""))) }
                    Button("Sub-menu") { add(RingItem(title: "New Menu", symbol: "folder", items: [])) }
                    Menu("Tool") {
                        ForEach(MiniAppID.allCases, id: \.self) { id in
                            Button(id.title) { add(RingConfig.item(id.title, id.symbol, .miniApp, id.rawValue)) }
                        }
                    }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
                Button { remove() } label: { Image(systemName: "minus") }.disabled(itemIndex == nil)
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled((itemIndex ?? 0) == 0)
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .disabled(itemIndex == nil || itemIndex == items.wrappedValue.count - 1)
                Spacer()
            }.buttonStyle(.borderless)
        }
    }

    private func add(_ item: RingItem) {
        items.wrappedValue.append(item)
        itemIndex = items.wrappedValue.count - 1
    }
    private func remove() {
        guard let i = itemIndex else { return }
        items.wrappedValue.remove(at: i)
        itemIndex = items.wrappedValue.isEmpty ? nil : min(i, items.wrappedValue.count - 1)
    }
    private func move(_ d: Int) {
        guard let i = itemIndex, (0..<items.wrappedValue.count).contains(i + d) else { return }
        items.wrappedValue.swapAt(i, i + d)
        itemIndex = i + d
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - One item

struct ItemEditor: View {
    @Binding var item: RingItem
    var openSubMenu: () -> Void
    @State private var shortcuts: [String] = []

    private enum Kind: String, CaseIterable, Identifiable {
        case app = "Open app", url = "Open link", shortcut = "Run Shortcut", miniApp = "Tool", window = "Move window"
        case system = "System action", appleScript = "AppleScript", menu = "Sub-menu"
        var id: String { rawValue }
    }

    private var kind: Binding<Kind> {
        Binding(get: {
            if item.isMenu || item.action == nil { return .menu }
            switch item.action!.type {
            case .app: return .app
            case .url: return .url
            case .shortcut: return .shortcut
            case .miniApp: return .miniApp
            case .window: return .window
            case .system: return .system
            case .appleScript: return .appleScript
            }
        }, set: { k in
            switch k {
            case .menu: item.action = nil; if item.items == nil { item.items = [] }
            case .app: set(.app, "")
            case .url: set(.url, "https://")
            case .shortcut: set(.shortcut, "")
            case .miniApp: set(.miniApp, MiniAppID.clipboard.rawValue)
            case .window: set(.window, WindowAction.leftHalf.rawValue)
            case .system: set(.system, SystemAction.toggleDarkMode.rawValue)
            case .appleScript: set(.appleScript, "")
            }
        })
    }

    private func set(_ t: RingAction.Kind, _ v: String) { item.items = nil; item.action = RingAction(type: t, value: v) }

    private var value: Binding<String> {
        Binding(get: { item.action?.value ?? "" }, set: { item.action?.value = $0 })
    }

    var body: some View {
        Form {
            TextField("Name", text: $item.title)
            HStack {
                TextField("Icon (SF Symbol)", text: $item.symbol)
                Image(systemName: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) == nil ? "questionmark.square.dashed" : item.symbol)
                    .font(.title2).frame(width: 30)
            }
            Picker("Does", selection: kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
            switch kind.wrappedValue {
            case .app:
                HStack {
                    TextField("App", text: value)
                    Button("Choose…") { chooseApp() }
                }
            case .url:
                TextField("Link", text: value)
            case .shortcut:
                Picker("Shortcut", selection: value) {
                    if !shortcuts.contains(value.wrappedValue) { Text(value.wrappedValue.isEmpty ? "Choose…" : value.wrappedValue).tag(value.wrappedValue) }
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
                .onAppear(perform: loadShortcuts)
            case .miniApp:
                Picker("Tool", selection: value) { ForEach(MiniAppID.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }
            case .window:
                Picker("Window", selection: value) { ForEach(WindowAction.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }
            case .system:
                Picker("Action", selection: value) {
                    Text("Toggle Dark Mode").tag(SystemAction.toggleDarkMode.rawValue)
                    Text("Lock Screen").tag(SystemAction.lockScreen.rawValue)
                    Text("Sleep Display").tag(SystemAction.sleepDisplay.rawValue)
                    Text("Empty Trash").tag(SystemAction.emptyTrash.rawValue)
                    Text("Eject All Disks").tag(SystemAction.ejectAll.rawValue)
                    Text("Sleep Mac").tag(SystemAction.sleepMac.rawValue)
                    Text("Mute / Unmute").tag(SystemAction.toggleMute.rawValue)
                    Text("Mission Control").tag(SystemAction.missionControl.rawValue)
                    Text("Show Desktop").tag(SystemAction.showDesktop.rawValue)
                    Text("Screen Saver").tag(SystemAction.screenSaver.rawValue)
                }
            case .appleScript:
                TextEditor(text: value).font(.system(.body, design: .monospaced)).frame(minHeight: 90)
            case .menu:
                Text("\(item.items?.count ?? 0) items inside").foregroundStyle(.secondary)
                Button("Edit items inside", action: openSubMenu)
            }
            if item.action != nil {
                Button("Try it") { if let a = item.action { ActionRunner.run(a) { msg in NSSound.beep(); print(msg) } } }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        guard p.runModal() == .OK, let url = p.url else { return }
        value.wrappedValue = url.path
        if item.title == "New Item" { item.title = url.deletingPathExtension().lastPathComponent }
    }

    private func loadShortcuts() {
        DispatchQueue.global().async {
            let pr = Process()
            pr.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            pr.arguments = ["list"]
            let pipe = Pipe()
            pr.standardOutput = pipe
            try? pr.run()
            pr.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let names = out.split(separator: "\n").map(String.init).sorted()
            DispatchQueue.main.async { shortcuts = names }
        }
    }
}

// MARK: - Hotkey recorder

struct HotkeyRecorder: View {
    @Binding var hotkey: HotkeyConfig
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : KeyCodes.describe(hotkey)) { recording ? stop() : start() }
            .help("Click, then press the new hotkey (with at least one of ⌃ ⌥ ⌘ ⇧). Esc cancels.")
            .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            var mods: [String] = []
            let f = e.modifierFlags
            if f.contains(.control) { mods.append("control") }
            if f.contains(.option) { mods.append("option") }
            if f.contains(.shift) { mods.append("shift") }
            if f.contains(.command) { mods.append("command") }
            guard let name = KeyCodes.table.first(where: { $0.value == Int(e.keyCode) })?.key else { NSSound.beep(); return nil }
            let isF = name.hasPrefix("f") && name.count > 1
            guard !mods.isEmpty || isF else { NSSound.beep(); return nil }
            hotkey = HotkeyConfig(key: name, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
