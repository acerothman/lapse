#!/bin/bash
# Builds Lapse.app with swiftc (no Xcode project) and ad-hoc signs it.
# With no arguments, installs to ~/Applications and opens the app.
# Pass --no-open to stop after the signed bundle in build/ (no install, no launch).
# Requires macOS 13+ and the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP=Lapse
BUILD=build
BUNDLE="$BUILD/$APP.app"
DEST="$HOME/Applications"
ARCH="$(uname -m)"          # arm64 or x86_64
TARGET="$ARCH-apple-macos13.0"

echo "→ Cleaning"
rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "→ Compiling ($TARGET)"
swiftc -O -swift-version 5 -parse-as-library \
  -target "$TARGET" \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework AppKit -framework SwiftUI -framework Charts \
  -framework ServiceManagement -framework UserNotifications \
  Sources/*.swift \
  -o "$BUNDLE/Contents/MacOS/$APP"

echo "→ Bundling resources"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/Icons/*.png "$BUNDLE/Contents/Resources/"

echo "→ Generating app icon"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$BUILD/icon_1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s           "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "→ Ad-hoc code signing"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --verbose=1 "$BUNDLE"

if [[ "${1:-}" == "--no-open" ]]; then
  echo "✓ Built $BUNDLE"
  exit 0
fi

echo "→ Installing to $DEST"
mkdir -p "$DEST"
pkill -x "$APP" 2>/dev/null || true
rm -rf "$DEST/$APP.app"
cp -R "$BUNDLE" "$DEST/"

echo "✓ Installed $DEST/$APP.app"
open "$DEST/$APP.app"
