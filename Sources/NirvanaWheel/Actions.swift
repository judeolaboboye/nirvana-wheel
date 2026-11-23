import AppKit

enum SystemAction: String, CaseIterable {
    case toggleDarkMode
    case lockScreen
    case emptyTrash
    case sleepDisplay
    case ejectAll
    case sleepMac
    case toggleMute
    case missionControl
    case showDesktop
    case screenSaver

    var script: String? {
        switch self {
        case .toggleDarkMode:
            return "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        case .emptyTrash:
            return "tell application \"Finder\" to empty trash"
        case .ejectAll:
            return "tell application \"Finder\" to eject (every disk whose ejectable is true)"
        case .lockScreen:
            // Control-Command-Q, the system's own lock shortcut.
            return "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        case .toggleMute:
            return "set volume output muted (not (output muted of (get volume settings)))"
        case .sleepDisplay, .sleepMac, .missionControl, .showDesktop, .screenSaver:
            return nil
        }
    }
}

/// Runs a ring item. Failures are reported through `onError` instead of crashing.
enum ActionRunner {
    static func run(_ action: RingAction, onError: @escaping (String) -> Void) {
        switch action.type {
        case .app:
            let url = URL(fileURLWithPath: (action.value as NSString).expandingTildeInPath)
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { onError("Couldn't open \(url.lastPathComponent): \(error.localizedDescription)") } }
            }
        case .url:
            guard let url = URL(string: action.value) else { return onError("Not a valid address: \(action.value)") }
            NSWorkspace.shared.open(url)
        case .shortcut:
            runProcess("/usr/bin/shortcuts", ["run", action.value], onError: onError)
        case .appleScript:
            runAppleScript(action.value, onError: onError)
        case .miniApp:
            guard let id = MiniAppID(rawValue: action.value) else { return onError("Unknown mini-app: \(action.value)") }
            MiniAppHost.shared.open(id)
        case .window:
            guard let w = WindowAction(rawValue: action.value) else { return onError("Unknown window action: \(action.value)") }
            // Let the ring disappear and focus settle on the target app first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { WindowMover.perform(w, onError: onError) }
        case .system:
            guard let sys = SystemAction(rawValue: action.value) else { return onError("Unknown system action: \(action.value)") }
            switch sys {
            case .sleepDisplay:
                runProcess("/usr/bin/pmset", ["displaysleepnow"], onError: onError)
            case .sleepMac:
                runProcess("/usr/bin/pmset", ["sleepnow"], onError: onError)
            case .missionControl:
                runProcess("/usr/bin/open", ["-a", "Mission Control"], onError: onError)
            case .showDesktop:
                // Hide every other app so the desktop shows (no permission needed).
                DispatchQueue.main.async {
                    for a in NSWorkspace.shared.runningApplications
                    where a.activationPolicy == .regular && a.bundleIdentifier != Bundle.main.bundleIdentifier
                        && a.bundleIdentifier != "com.apple.finder" { a.hide() }
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Desktop"))
                }
            case .screenSaver:
                runProcess("/usr/bin/open", ["-a", "ScreenSaverEngine"], onError: onError)
            default:
                if let s = sys.script { runAppleScript(s, onError: onError) }
            }
        }
    }

    private static func runAppleScript(_ source: String, onError: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let err, let msg = err[NSAppleScript.errorMessage] as? String {
                DispatchQueue.main.async { onError(msg) }
            }
        }
    }

    private static func runProcess(_ path: String, _ args: [String], onError: @escaping (String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                DispatchQueue.main.async { onError("\((path as NSString).lastPathComponent) \(args.joined(separator: " ")) failed (\(proc.terminationStatus))") }
            }
        }
        do { try p.run() } catch { onError(error.localizedDescription) }
    }
}
