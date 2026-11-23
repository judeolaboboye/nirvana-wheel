# Nirvana Wheel roadmap

Everything The Orbs does, rebuilt in Jude's own app from scratch. Tick = built, tested (`swift test`, 22 tests)
and in the app. "Needs Jude to try" = works in code and tests but needs a real hand on the keys/trackpad.

## 1. Core ring
- [x] Menu-bar app, no Dock icon, own icon (2026-11-22)
- [x] Hold a hotkey, point, release to run; release in the centre cancels
- [x] Ring opens under the pointer, stays on screen near edges, light haptic tick per item
- [x] Sub-menus: push out past an item to open its ring, back to the centre to go back
- [x] Several rings (profiles), each with its own hotkey
- [x] Settings window: rings, hotkey recorder, add / remove / reorder / nest items, app chooser, Shortcut list,
      icon preview, "Try it"
- [x] Export / Import setup (menu bar), Reset to Default (keeps a backup)
- [x] Open at Login

## 2. Triggers
- [x] Hotkey (no permission needed)
- [x] Extra mouse button (middle / back / forward), set in Settings. Needs Jude to try
- [x] Four-finger hold on the trackpad opens the ring in click-to-choose mode (menu bar toggle). Uses Apple's
      private multitouch framework, loaded only if present. Needs Jude to try

## 3. Tools (mini-apps), all on the ring under "Tools" and in the menu bar
- [x] Clipboard History: searchable, pin, skips password-manager secrets, keeps 200
- [x] Shelf: drop files in, drag them out; add the Finder selection; optional "catch new screenshots"
- [x] Timer with sound and alert
- [x] Calculator (own safe maths parser, copies results)
- [x] Colour Picker (pick from screen, HEX and RGB)
- [x] Scratchpad (saved as you type)
- [x] QR Code maker (drag or copy the image)
- [x] QR Scanner (drag over part of the screen)
- [x] Mirror (camera)
- [x] Mic Check (live level with too-quiet / too-loud hint)
- [x] Sound: switch output and input device, volume
- [x] Stay Awake (30 min / 1 h / 3 h / always)
- [x] Focus: dims everything except the front window
- [x] Magnifier (needs Screen Recording permission)
- [x] System Glance: CPU, memory, disk, battery

## 4. Windows and system
- [x] Windows: left / right / top / bottom half, fill, centre, next display (needs Accessibility permission)
- [x] System: Dark Mode, Lock Screen, Sleep Display, Sleep Mac, Mute, Mission Control, Show Desktop,
      Empty Trash, Eject All, Screen Saver

## Checked on screen (2026-11-22)
Settings window and 12 tools captured with `--snapshot <dir>` (opens them behind everything and quits): all draw
correctly with live data (System Glance read 55% CPU, 6.2 of 8 GB, 80% battery; Sound found MacBook Pro Speakers).
The ring itself was seen on screen earlier. Mirror, Mic Check and Magnifier ask for permission first, so they
wait for Jude.

## Made easier to find (2026-11-22, v0.3, after Jude couldn't find it)
- [x] Installed in /Applications; normal app with a Dock icon and home window ("Open the Wheel" button, keys, tool buttons)
- [x] Dock right-click menu and app menu: Open the Wheel (⌘O), Settings

## Fixes from Jude's try (2026-11-22)
- [x] Show Desktop: "Mission Control 1 failed (9)" fixed, now hides other apps instead
- [x] Mirror / Mic Check / Magnifier: cause found in logs: ad-hoc signature changes every build, so macOS drops the
      permission ("Failed to match existing code requirement"). Tools now show a clear note + Open System Settings.
- [x] Stable signing with the "BetterVoice Local Signing" identity (bundle.sh), approved by Jude 2026-11-22:
      permissions now survive rebuilds
- [x] "The wheel did not do as I asked" (Jude): in click mode, clicks went to the app behind the wheel. Cause: the
      invisible click-catching window was so transparent macOS let clicks through. First fix (faint tint) was not enough:
      Jude still saw clicks go through. Real fix v0.3.3: the catcher's own view takes every click including the first
      one while another app is in front (acceptsFirstMouse), plus a light dim. Proven with a synthetic click: before,
      the wheel stayed open (click went elsewhere); after, the middle click closed it

## 5. Left to Jude
- [x] Final name: Nirvana Wheel (Jude, 2026-11-22). App id com.jude.nirvanawheel, data in ~/Library/Application Support/NirvanaWheel
- [x] Tried by hand (2026-11-22): the wheel opens and runs items. Found: in click mode, going back out of a sub-menu
      didn't work. Fixed: click the middle inside a sub-menu to go back (v0.3.1), proven by
      `ClickModeTests` (opens Tools, middle-click goes back, middle-click again closes). Jude will adjust the items himself over time.
      Four-finger hold: `--trackpad-check` shows the touch framework loads and finds 2 touch devices on this Mac
      (2026-11-22), so the gesture can read the trackpad; the finger hold itself is for Jude to feel.
      Not tried yet by him: four-finger trackpad hold, mouse button, Mirror / Mic Check / Magnifier
      (those three need him to allow camera / microphone / screen access, which only he can grant).

## Not included on purpose
- The Orbs' licence check, accounts, analytics and auto-updater: not needed in Jude's own app.
