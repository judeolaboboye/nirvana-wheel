import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var loginMenuItem: NSMenuItem!
    private var trackpadMenuItem: NSMenuItem!
    private var hotkeyHeader: NSMenuItem!
    private let ring = RingController()
    private var hotKeys: [HotKey] = []
    private let mouse = MouseTrigger()
    private(set) var config = RingConfig.default
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--snapshot <dir>`: separate check run. Opens the windows behind everything, captures them, quits.
        // Registers no hotkeys and touches no settings, so it can run next to the real app.
        let a = CommandLine.arguments
        // `--trackpad-check`: does the trackpad gesture reach the trackpad? Prints the result and quits.
        if a.contains("--trackpad-check") {
            TrackpadTrigger.shared.start()
            print("trackpad devices found: \(TrackpadTrigger.shared.deviceCount), gesture available: \(TrackpadTrigger.shared.available)")
            TrackpadTrigger.shared.stop()
            exit(0)
        }
        if let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshotter.run(dir: URL(fileURLWithPath: a[i + 1]), config: ConfigStore.load().0) }
            return
        }
        ring.onError = { [weak self] msg in self?.showError(msg) }
        TrackpadTrigger.shared.onGesture = { [weak self] in
            guard let self, let first = self.config.profiles.first else { return }
            self.ring.open(items: first.items, sticky: true)
        }
        setUpMenu()
        reload()
        ClipboardStore.shared.start()
        // `--open <mini-app>` opens one straight away (used to check each tool); `--ring` shows the ring briefly.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let id = MiniAppID(rawValue: args[i + 1]) {
            MiniAppHost.shared.open(id)
        }
        if args.contains("--click-mode") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openWheelByClick() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.ring.close() }
        }
        if args.contains("--ring"), let first = config.profiles.first {
            ring.open(items: first.items)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.ring.close() }
        }
        if args.contains("--settings") { openSettings() }
        setUpMainMenu()
        // Opening the app shows its home window (it also lives in the Dock and the menu bar).
        if !args.contains("--quiet") { showWelcome() }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows the welcome window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return false
    }

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Nirvana Wheel"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(
                openSettings: { [weak self] in self?.openSettings() },
                showWheel: { [weak self] in self?.openWheelByClick() }))
            if let v = w.contentView { w.setContentSize(v.fittingSize) } // fit the content exactly
            w.center()
            welcomeWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu

    /// The normal app menu at the top of the screen when Nirvana Wheel is in front.
    private func setUpMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open the Wheel", action: #selector(openWheelByClick), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "Home", action: #selector(showWelcome), keyEquivalent: "1").target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Nirvana Wheel", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Nirvana Wheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Opens the first wheel in click-to-choose mode, so it can be used with the mouse alone.
    @objc func openWheelByClick() {
        guard let first = config.profiles.first else { return }
        welcomeWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.ring.open(items: first.items, sticky: true)
        }
    }

    /// Dock icon right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Open the Wheel", action: #selector(openWheelByClick), keyEquivalent: "").target = self
        m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        return m
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Nirvana Wheel")
        let menu = NSMenu()
        hotkeyHeader = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hotkeyHeader.isEnabled = false
        menu.addItem(hotkeyHeader)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "How to Use…", action: #selector(showWelcome), keyEquivalent: "").target = self
        let tools = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu()
        for id in MiniAppID.allCases {
            let it = NSMenuItem(title: id.title, action: #selector(openTool(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = id.rawValue
            it.image = NSImage(systemSymbolName: id.symbol, accessibilityDescription: nil)
            toolsMenu.addItem(it)
        }
        tools.submenu = toolsMenu
        menu.addItem(tools)
        menu.addItem(.separator())
        trackpadMenuItem = NSMenuItem(title: "Four-Finger Hold Opens the Ring", action: #selector(toggleTrackpad), keyEquivalent: "")
        trackpadMenuItem.target = self
        menu.addItem(trackpadMenuItem)
        loginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginMenuItem.target = self
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export Setup…", action: #selector(exportSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Import Setup…", action: #selector(importSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Edit Settings File", action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload", action: #selector(reloadAction), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Reset to Default…", action: #selector(resetConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nirvana Wheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: Applying settings

    func apply(_ cfg: RingConfig, save: Bool) {
        if save { ConfigStore.save(cfg) }
        config = cfg
        ring.close()
        hotKeys = []
        var problems: [String] = []
        var names: [String] = []
        for p in cfg.profiles {
            let desc = KeyCodes.describe(p.hotkey)
            if let code = KeyCodes.table[p.hotkey.key.lowercased()],
               let hk = HotKey(keyCode: UInt32(code), carbonModifiers: KeyCodes.carbonModifiers(p.hotkey.modifiers)) {
                let items = p.items
                hk.onPress = { [weak self] in self?.ring.open(items: items) }
                hk.onRelease = { [weak self] in self?.ring.release() }
                hotKeys.append(hk)
                names.append("\(desc) \(p.name)")
            } else {
                problems.append("\(desc) (\(p.name))")
            }
        }
        hotkeyHeader.title = names.isEmpty ? "No hotkey active" : "Hold " + names.joined(separator: " · ")
        if let b = cfg.mouseButton, let first = cfg.profiles.first {
            mouse.onPress = { [weak self] in self?.ring.open(items: first.items) }
            mouse.onRelease = { [weak self] in self?.ring.release() }
            mouse.start(button: b)
        } else {
            mouse.stop()
        }
        if cfg.trackpadGesture { TrackpadTrigger.shared.start() } else { TrackpadTrigger.shared.stop() }
        trackpadMenuItem.state = cfg.trackpadGesture ? .on : .off
        if !problems.isEmpty {
            showError("These hotkeys couldn't be set (another app may use them): \(problems.joined(separator: ", ")). Change them in Settings.")
        }
    }

    private func reload() {
        let (cfg, error) = ConfigStore.load()
        apply(cfg, save: false)
        if let error { showError(error) }
    }

    // MARK: Actions

    @objc private func openTool(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let id = MiniAppID(rawValue: raw) { MiniAppHost.shared.open(id) }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Nirvana Wheel Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(initial: config) { [weak self] new in self?.apply(new, save: true) })
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleTrackpad() {
        var c = config
        c.trackpadGesture.toggle()
        apply(c, save: true)
        if c.trackpadGesture && !TrackpadTrigger.shared.available {
            showError("The trackpad gesture isn't available on this Mac.")
        }
    }

    @objc private func reloadAction() { reload() }

    @objc private func exportSetup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Nirvana Wheel Setup.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try FileManager.default.removeItem(at: url) } catch {}
        do { try FileManager.default.copyItem(at: ConfigStore.fileURL, to: url) }
        catch { showError("Couldn't export: \(error.localizedDescription)") }
    }

    @objc private func importSetup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let cfg = try JSONDecoder().decode(RingConfig.self, from: Data(contentsOf: url))
            backUpConfig()
            apply(cfg, save: true)
            settingsWindow?.close(); settingsWindow = nil
        } catch {
            showError("That file isn't a Nirvana Wheel setup: \(error.localizedDescription)")
        }
    }

    private func backUpConfig() {
        let fm = FileManager.default
        let backup = ConfigStore.directory.appendingPathComponent("config.backup.json")
        try? fm.removeItem(at: backup)
        try? fm.copyItem(at: ConfigStore.fileURL, to: backup)
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "Reset Nirvana Wheel to the default rings?"
        alert.informativeText = "Your current setup is kept next to it as config.backup.json."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        backUpConfig()
        apply(.default, save: true)
        settingsWindow?.close(); settingsWindow = nil
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            showError("Couldn't change Open at Login: \(error.localizedDescription)")
        }
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func editConfig() { NSWorkspace.shared.open(ConfigStore.fileURL) }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Nirvana Wheel"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Captures windows with the system `screencapture -l <window id>` without bringing them forward.
@MainActor enum Snapshotter {
    static func run(dir: URL, config: RingConfig) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var windows: [(String, NSWindow)] = []
        func make<V: View>(_ name: String, _ view: V, _ size: CGSize) {
            let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 60 + windows.count * 20, y: 60), size: size),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = name
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            w.orderBack(nil)
            windows.append((name, w))
        }
        make("Settings", SettingsView(initial: config) { _ in }, CGSize(width: 760, height: 520))
        make("Welcome", WelcomeView(openSettings: {}, showWheel: {}), CGSize(width: 560, height: 520))
        let quiet: [MiniAppID] = [.clipboard, .shelf, .timer, .calculator, .colorPicker, .scratchpad, .qrMaker,
                                  .qrScanner, .audio, .caffeine, .focus, .systemGlance]
        for id in quiet { make(id.rawValue, id.makeView(), id.size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            for (name, w) in windows {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(w.windowNumber), dir.appendingPathComponent("\(name).png").path]
                try? p.run(); p.waitUntilExit()
            }
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // Dock icon + menu bar icon, so it's easy to find
app.run()
