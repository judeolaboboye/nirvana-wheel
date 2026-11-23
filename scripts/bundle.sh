#!/bin/zsh
# Builds Nirvana Wheel and wraps it as build/Nirvana Wheel.app (menu-bar app, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Nirvana Wheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NirvanaWheel "$APP/Contents/MacOS/NirvanaWheel"
[ -f Resources/AppIcon.icns ] || swift scripts/make_icon.swift Resources
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>NirvanaWheel</string>
  <key>CFBundleIdentifier</key><string>com.jude.nirvanawheel</string>
  <key>CFBundleName</key><string>Nirvana Wheel</string>
  <key>CFBundleDisplayName</key><string>Nirvana Wheel</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSCameraUsageDescription</key><string>Nirvana Wheel shows your camera in the Mirror tool.</string>
  <key>NSMicrophoneUsageDescription</key><string>Nirvana Wheel shows your microphone level in Mic Check.</string>
  <key>NSAppleEventsUsageDescription</key><string>Nirvana Wheel runs the system actions you put on the ring, like toggling Dark Mode or emptying the Trash.</string>
</dict></plist>
PLIST
# Sign with a fixed local identity when there is one, so macOS keeps camera / microphone / screen permissions across
# rebuilds (an ad-hoc "-" signature changes every build and macOS then forgets the permission).
SIGN_ID="${SIGN_ID:-BetterVoice Local Signing}"
if security find-identity -v -p codesigning | grep -q "\"$SIGN_ID\""; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "No '$SIGN_ID' identity: signing ad-hoc (permissions will need re-allowing after each build)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
