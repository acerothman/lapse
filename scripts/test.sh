#!/bin/bash
# Compiles the model and store code with Tests/LapseTests.swift and runs the checks.
# Uses a throwaway data folder, so your own Lapse data is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Sources/Models.swift Sources/FeedRules.swift Sources/Store.swift Sources/Links.swift \
  Sources/Favicon.swift Sources/StatusLabel.swift \
  Tests/LapseTests.swift \
  -o "$OUT/lapse-tests"

LAPSE_DATA_DIR="$OUT/data" "$OUT/lapse-tests"
