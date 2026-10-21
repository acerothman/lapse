#!/bin/bash
# Builds Lapse.app with swiftc (no Xcode project) and ad-hoc signs it.
# With no arguments, installs to ~/Applications and opens the app.
# Pass --no-open to stop after the signed bundle in build/ (no install, no launch).
# Requires macOS 13+ and the Command Line Tools (xcode-select --install).
# With full Xcode selected, it also writes the App Intents metadata that Shortcuts
# and Focus filters need. Without Xcode the app still builds, minus those.
set -euo pipefail
cd "$(dirname "$0")"

APP=Lapse
BUILD=build
BUNDLE="$BUILD/$APP.app"
DEST="$HOME/Applications"
ARCH="$(uname -m)"          # arm64 or x86_64
TARGET="$ARCH-apple-macos13.0"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

echo "→ Cleaning"
rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUILD/intents"

# App Intents: the compiler records constant values for these protocols, and Xcode's
# extractor turns them into Metadata.appintents inside the bundle.
cat > "$BUILD/intents/protocols.json" <<'JSON'
["AnyResolverProviding", "AppEntity", "AppEnum", "AppIntent", "AppIntentsPackage", "AppShortcutProviding",
 "AppShortcutsProvider", "DynamicOptionsProvider", "EntityQuery", "IntentValueQuery", "Resolver",
 "TransientEntity", "_AssistantIntentsProvider", "_GenerativeFunctionExtractable", "_IntentValueRepresentable"]
JSON

echo "→ Compiling ($TARGET)"
swiftc -O -wmo -swift-version 5 -parse-as-library \
  -module-name "$APP" \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework AppKit -framework SwiftUI -framework Charts -framework AppIntents \
  -framework ServiceManagement -framework UserNotifications \
  -emit-const-values-path "$BUILD/intents/$APP.swiftconstvalues" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "$BUILD/intents/protocols.json" \
  Sources/*.swift \
  -o "$BUNDLE/Contents/MacOS/$APP"

echo "→ Bundling resources"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/Icons/*.png "$BUNDLE/Contents/Resources/"

if EXTRACTOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
  echo "→ Extracting App Intents metadata"
  for f in Sources/*.swift; do echo "$PWD/$f"; done > "$BUILD/intents/sources.txt"
  echo "$PWD/$BUILD/intents/$APP.swiftconstvalues" > "$BUILD/intents/constvalues.txt"
  XCODE_BUILD="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
  # Older Xcode versions lack some flags. Pass only the ones this extractor knows.
  HELP="$("$EXTRACTOR" --help 2>&1 || true)"
  EXTRA=()
  for flag in --force --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization; do
    if grep -q -- "$flag" <<<"$HELP"; then EXTRA+=("$flag"); fi
  done
  "$EXTRACTOR" \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$EXTRACTOR")")")" \
    --module-name "$APP" \
    --sdk-root "$SDK" \
    --xcode-version "${XCODE_BUILD:-unknown}" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --bundle-identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)" \
    --output "$BUNDLE/Contents/Resources" \
    --target-triple "$TARGET" \
    --binary-file "$BUNDLE/Contents/MacOS/$APP" \
    --dependency-file "$BUILD/intents/deps.d" \
    --stringsdata-file "$BUILD/intents/ExtractedAppShortcutsMetadata.stringsdata" \
    --source-file-list "$BUILD/intents/sources.txt" \
    --swift-const-vals-list "$BUILD/intents/constvalues.txt" \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    2>&1 | grep -v 'appintentsmetadataprocessor\[' || true
  if [[ ! -d "$BUNDLE/Contents/Resources/Metadata.appintents" ]]; then
    echo "error: App Intents metadata was not written" >&2
    exit 1
  fi
else
  echo "→ Skipping App Intents metadata (needs Xcode). Shortcuts and Focus filters won't see Lapse."
fi

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
