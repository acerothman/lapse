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
SDK="$(xcrun --show-sdk-path --sdk macosx)"
CONST="$BUILD/Lapse.swiftconstvalues"
compile_app() {
  swiftc -swift-version 5 -parse-as-library \
    -module-name Lapse \
    -target "$TARGET" \
    -sdk "$SDK" \
    "$@" \
    -framework AppKit -framework SwiftUI -framework Charts \
    -framework ServiceManagement -framework UserNotifications -framework AppIntents \
    Sources/*.swift \
    -o "$BUNDLE/Contents/MacOS/$APP"
}
# Const extraction only walks the primary file. Intents.swift is that file.
OTHERS=()
for f in Sources/*.swift; do
  [[ "$f" == Sources/Intents.swift ]] && continue
  OTHERS+=("$f")
done
echo "→ Extracting App Intents metadata inputs"
swiftc -typecheck -swift-version 5 -parse-as-library \
  -module-name Lapse \
  -target "$TARGET" \
  -sdk "$SDK" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "scripts/appintents-protocols.json" \
  -Xfrontend -emit-const-values-path -Xfrontend "$CONST" \
  -framework AppKit -framework SwiftUI -framework Charts \
  -framework ServiceManagement -framework UserNotifications -framework AppIntents \
  -primary-file Sources/Intents.swift \
  "${OTHERS[@]}"
compile_app -O

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

echo "→ App Intents metadata"
DEVROOT="$(xcode-select -p)"
TOOLCHAIN="$DEVROOT/Toolchains/XcodeDefault.xctoolchain"
if ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  echo "appintentsmetadataprocessor not found" >&2
  exit 1
fi
XCODE_BUILD="$(xcodebuild -version 2>/dev/null | awk '/Build version/ { print $3; exit }')"
META_OUT="$BUNDLE/Contents/Resources/Metadata.appintents"
run_metadata() {
  local mode="$1"
  local -a args
  args=(xcrun appintentsmetadataprocessor
    --output "$BUNDLE/Contents/Resources"
    --toolchain-dir "$TOOLCHAIN"
    --module-name Lapse
    --sdk-root "$SDK"
    --target-triple "$TARGET"
    --binary-file "$BUNDLE/Contents/MacOS/$APP"
    --deployment-target 13.0
    --platform-family macOS)
  if [[ -n "$XCODE_BUILD" ]]; then
    args+=(--xcode-version "$XCODE_BUILD")
  fi
  local f
  for f in Sources/*.swift; do
    args+=(--source-files "$f")
  done
  if [[ "$mode" == "modern" && -f "$CONST" ]]; then
    args+=(--compile-time-extraction --swift-const-vals "$CONST")
  fi
  echo "metadata ($mode)"
  "${args[@]}"
}
metadata_ready() {
  [[ -d "$META_OUT" ]] && find "$META_OUT" -type f | grep -q .
}
if [[ -f "$CONST" ]]; then
  rm -rf "$META_OUT"
  run_metadata modern || true
fi
if ! metadata_ready; then
  rm -rf "$META_OUT"
  run_metadata legacy
fi
if ! metadata_ready; then
  echo "App Intents metadata was not written" >&2
  if [[ -f "$CONST" ]]; then
    echo "const values file: $(wc -c < "$CONST") bytes"
    head -c 1500 "$CONST" || true
    echo
  else
    echo "const values file was not produced"
  fi
  exit 1
fi

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
