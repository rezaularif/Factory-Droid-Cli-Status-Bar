#!/bin/bash
# Builds DroidStatusBar.app (optional: ./build.sh --dmg).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DroidStatusBar.app"
BIN="$APP/Contents/MacOS/DroidStatusBar"
VERSION="0.2.6"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling universal binary (arm64 + x86_64)…"
swiftc -O -target arm64-apple-macos12.0  Sources/*.swift -o "$BIN.arm64"  -framework Cocoa
swiftc -O -target x86_64-apple-macos12.0 Sources/*.swift -o "$BIN.x86_64" -framework Cocoa
lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DroidStatusBar</string>
  <key>CFBundleDisplayName</key><string>Droid Status Bar</string>
  <key>CFBundleIdentifier</key><string>com.local.droidstatusbar</string>
  <key>CFBundleExecutable</key><string>DroidStatusBar</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources/lib"
cp hooks/update.js hooks/lifecycle.js hooks/install.js hooks/uninstall.js "$APP/Contents/Resources/"
cp hooks/lib/common.js "$APP/Contents/Resources/lib/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Droid CLI animation assets
cp assets/droid-logo-frames.json assets/droid-spinners.json "$APP/Contents/Resources/" 2>/dev/null || true

xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP (v${VERSION})"

if [[ "${1:-}" == "--dmg" ]]; then
  echo "Packaging DMG…"
  DMG="build/DroidStatusBar.dmg"
  STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Droid Status Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Built $DMG"
fi
