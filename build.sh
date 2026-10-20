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
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUNDLE/Contents/Frameworks"

SPARKLE_VERSION=2.10.0
SPARKLE_CACHE="${HOME}/.cache/lapse-sparkle-${SPARKLE_VERSION}"
if ! find "$SPARKLE_CACHE" -name Sparkle.framework -type d -print -quit 2>/dev/null | grep -q .; then
  echo "→ Downloading Sparkle ${SPARKLE_VERSION}"
  mkdir -p "$SPARKLE_CACHE"
  curl -fsSL --retry 3 -o "$SPARKLE_CACHE/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  tar -xJf "$SPARKLE_CACHE/sparkle.tar.xz" -C "$SPARKLE_CACHE"
fi
# The tarball also nests a Sparkle.framework inside the test app, and that copy has no module map.
FRAMEWORK="$SPARKLE_CACHE/Sparkle.framework"
if [[ ! -e "$FRAMEWORK/Versions/B/Modules/module.modulemap" ]]; then
  echo "Sparkle.framework module map not found in $SPARKLE_CACHE" >&2
  find "$SPARKLE_CACHE" -name module.modulemap -print >&2 || true
  exit 1
fi
FWDIR=$(dirname "$FRAMEWORK")
echo "→ Sparkle at $FRAMEWORK"

echo "→ Compiling ($TARGET)"
swiftc -O -swift-version 5 -parse-as-library \
  -target "$TARGET" \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -F "$FWDIR" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -framework AppKit -framework SwiftUI -framework Charts \
  -framework ServiceManagement -framework UserNotifications \
  Sources/*.swift \
  -o "$BUNDLE/Contents/MacOS/$APP"

echo "→ Bundling resources"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/Icons/*.png "$BUNDLE/Contents/Resources/"
cp -R "$FRAMEWORK" "$BUNDLE/Contents/Frameworks/"

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
# Ad hoc only. Not notarized. --deep covers Sparkle's nested helper tools.
codesign --force --deep --sign - "$BUNDLE/Contents/Frameworks/Sparkle.framework"
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
