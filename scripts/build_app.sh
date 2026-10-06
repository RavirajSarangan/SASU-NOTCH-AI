#!/bin/zsh
# Builds Nova.app from the Swift package (no Xcode required).
#   scripts/build_app.sh            release build → build/Nova.app
#   scripts/build_app.sh debug      debug build
#   UNIVERSAL=1 scripts/build_app.sh  arm64 + x86_64 (used by release.sh)
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Nova.app"
VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

SWIFT_ARGS=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  SWIFT_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Nova" "$APP/Contents/MacOS/Nova"
cp -R "$BIN/Nova_Nova.bundle" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Helpers"
cp "$BIN/nova-hook" "$APP/Contents/Helpers/nova-hook"
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nova</string>
    <key>CFBundleDisplayName</key><string>Nova</string>
    <key>CFBundleIdentifier</key><string>app.nova.companion</string>
    <key>CFBundleExecutable</key><string>Nova</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Nova</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAudioCaptureUsageDescription</key><string>Nova listens to Spotify or Music only to dance on the beat. Audio is analysed on your Mac and never saved or sent.</string>
    <key>NSMicrophoneUsageDescription</key><string>Nova listens only while you talk to it (hold ⌥ Space or say “Hey Nova”). Speech is recognised on your Mac and never saved.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Nova turns what you say into commands on your Mac, offline. Audio is never sent or stored.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Nova reads your calendar to answer “what's next?” and to remind you 5 minutes before meetings. Events never leave your Mac.</string>
    <key>NSRemindersFullAccessUsageDescription</key><string>Nova adds reminders when you ask (“remind me at 5 to call Amma”).</string>
    <key>NSAppleEventsUsageDescription</key><string>Nova controls Spotify playback from the notch.</string>
</dict>
</plist>
PLIST

# Sign with the local "Nova Local" identity when it exists (scripts/make_signing_cert.sh):
# a stable identity means macOS keeps Keychain and privacy permissions across
# rebuilds. Otherwise ad-hoc, which asks again after each build.
IDENTITY="-"
if security find-certificate -c "Nova Local" >/dev/null 2>&1; then IDENTITY="Nova Local"; fi
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/nova-hook" >/dev/null
codesign --force --sign "$IDENTITY" "$APP" >/dev/null

# Keep an already-installed Claude Code hook helper up to date (the hook
# settings themselves are only changed by install_claude_hook.sh).
INSTALLED_HOOK="$HOME/Library/Application Support/Nova/bin/nova-hook"
if [[ -f "$INSTALLED_HOOK" ]]; then
  cp "$APP/Contents/Helpers/nova-hook" "$INSTALLED_HOOK"
  echo "Updated $INSTALLED_HOOK"
fi
echo "Built $APP ($VERSION build $BUILD_NUMBER, $(lipo -archs "$APP/Contents/MacOS/Nova"))"
