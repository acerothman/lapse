#!/bin/bash
# Signs a release zip with Sparkle's EdDSA key and writes appcast.xml.
# The private key is read from SPARKLE_EDDSA_PRIVATE_KEY (one base64 line).
# It is not printed. CI skips this script when that secret is empty.
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Usage: scripts/make_appcast.sh Lapse-1.1.0.zip" >&2
  exit 1
fi
if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_EDDSA_PRIVATE_KEY is not set" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
SPARKLE_VERSION=2.10.0
CACHE="${HOME}/.cache/lapse-sparkle-${SPARKLE_VERSION}"
SIGN=$(find "$CACHE" -name sign_update -type f -print -quit)
if [[ -z "$SIGN" ]]; then
  echo "sign_update not found. Run ./build.sh once so Sparkle is downloaded." >&2
  exit 1
fi
chmod +x "$SIGN"

SIG_LINE=$(printf '%s\n' "$SPARKLE_EDDSA_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")
ED=$(printf '%s\n' "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(printf '%s\n' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
if [[ -z "$ED" || -z "$LENGTH" ]]; then
  echo "sign_update did not return a signature" >&2
  exit 1
fi

PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
URL="https://github.com/acerothman/lapse/releases/download/v${VERSION}/Lapse-${VERSION}.zip"

cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Lapse</title>
    <link>https://github.com/acerothman/lapse/releases</link>
    <description>Updates for Lapse</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <ul>
          <li>Track Mac apps you pick, with their own icons.</li>
          <li>A calm screen when a limit is reached. Snooze it, or turn it off for the day.</li>
          <li>A limit for each site and app, plus focus hours.</li>
        </ul>
      ]]></description>
      <enclosure
        url="${URL}"
        sparkle:edSignature="${ED}"
        length="${LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Wrote appcast.xml for ${VERSION} (${BUILD}), ${LENGTH} bytes"
