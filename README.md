# Nirvana Wheel

Jude's own radial launcher for the Mac. Hold a hotkey, a ring appears under the pointer, point at an
item, let go to run it. Written from scratch: the feature list came from studying The Orbs with REA
(`../REA/reports/the-orbs.md`), but no code, icons, fonts or design are copied, and there is no licence system.

## Use it
- Installed in **/Applications** (find it with Spotlight: ⌘Space, "Nirvana"). Opening it shows its **home window** with a big
  **Open the Wheel** button and the keys. It has a Dock icon and a menu-bar icon; closing the window keeps it running. Turn on **Open at Login** in the menu.
- **Hold ⌃⌥Space**, move towards an item, **let go** to run it. Let go in the middle to cancel.
- Items with a small arrow are sub-menus: keep moving outwards past them to open them, back to the middle to go back.
- Default ring: Finder, Safari, Terminal, Dark Mode, **Windows** (snap), **System** (lock, sleep, mute…),
  **Tools** (all 15 mini-apps), Settings.
- **Settings…** (menu bar, ⌘,) to change everything: rings, hotkeys, items, mouse button, trackpad gesture.
  Press **Save** to apply.
- The tools are also in the menu bar under **Tools**.

## Permissions macOS will ask for (only when you first use that thing)
| For | Permission |
|---|---|
| Dark Mode, Lock Screen, Empty Trash, Eject, Shelf "Add Finder selection" | Automation (System Events / Finder) |
| Window snapping | Accessibility |
| Mirror / Mic Check | Camera / Microphone |
| Magnifier | Screen Recording |
The hotkey, mouse button, trackpad gesture and the other tools need nothing.

## Triggers
- **Hotkey**: per ring, recorded in Settings.
- **Mouse button**: Settings → "Also open the first ring with". Hold, point, release. The click still reaches the app
  underneath, so a side button is best.
- **Trackpad**: menu bar → "Four-Finger Hold Opens the Ring". Rest four fingers for a moment; the ring opens in
  click-to-choose mode (move the pointer, click an item; click the middle or press Esc to cancel). Uses Apple's
  private multitouch framework, so it could stop working after a macOS update; everything else would still work.

## Settings file
`~/Library/Application Support/NirvanaWheel/config.json` (Settings writes it for you). Shape:
```json
{
  "profiles": [
    { "name": "Main", "hotkey": { "key": "space", "modifiers": ["control", "option"] },
      "items": [
        { "title": "Safari", "symbol": "safari", "action": { "type": "app", "value": "/Applications/Safari.app" } },
        { "title": "Tools", "symbol": "square.grid.2x2", "items": [
            { "title": "Timer", "symbol": "timer", "action": { "type": "miniApp", "value": "timer" } } ] }
      ] }
  ],
  "mouseButton": 3,
  "trackpadGesture": false
}
```
Action types: `app`, `url`, `shortcut`, `appleScript`, `system`, `miniApp`, `window`. Other data (clipboard history,
scratchpad, shelf) is kept in the same folder.

## Build
```
swift build && swift test        # 21 tests, includes drawing every window off-screen
./scripts/bundle.sh              # makes build/Nirvana Wheel.app (ad-hoc signed, own icon)
rm -rf "/Applications/Nirvana Wheel.app" && cp -R "build/Nirvana Wheel.app" /Applications/   # install
swift scripts/make_icon.swift Resources   # redraw the icon
```
8 GB Mac: one build at a time, close Ghidra/REA first. `--open <tool>`, `--ring`, `--settings` launch arguments open
one thing straight away for checking.

## Code
| File | What it does |
|---|---|
| `WheelGeometry.swift` | Which item the pointer is on (pure maths) |
| `RingView.swift` / `RingController.swift` | Drawing the ring; showing it, following the pointer, sub-menus, click mode |
| `HotKey.swift` / `Triggers.swift` | Hotkeys; mouse button; trackpad gesture |
| `Actions.swift` / `Windows.swift` | Running apps, links, Shortcuts, scripts, system actions; window snapping |
| `Config.swift` / `SettingsView.swift` | Settings file (rings) and the Settings window |
| `MiniApps/` | The 15 tools and the small floating window they open in |
| `main.swift` | Menu-bar app |

Progress: `ROADMAP.md`.
