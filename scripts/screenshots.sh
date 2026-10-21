#!/bin/bash
# Captures the README screenshots from the real app, filled with made-up data.
# Each scene launches build/Lapse.app with its own empty data folder, so your own
# Lapse data is never read or changed. Your terminal needs Screen Recording access.
# Usage: scripts/screenshots.sh [output dir, default docs]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs}"
mkdir -p "$OUT"
[[ -x build/Lapse.app/Contents/MacOS/Lapse ]] || ./build.sh --no-open
BIN="$PWD/build/Lapse.app/Contents/MacOS/Lapse"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT

shoot() {
  local scene=$1 appearance=$2 file=$3 flags=${4:-}
  rm -rf "${DATA:?}"/*
  LAPSE_DATA_DIR="$DATA" LAPSE_SCENE="$scene" LAPSE_APPEARANCE="$appearance" \
    LAPSE_SCENE_OUT="$DATA/window" "$BIN" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 60); do [[ -s "$DATA/window" ]] && break; sleep 0.2; done
  if [[ -s "$DATA/window" ]]; then
    local target
    target="$(cat "$DATA/window")"
    if [[ "$target" == R:* ]]; then
      # A screen region, for the popover over its backdrop.
      screencapture -x -R"${target#R:}" "$OUT/$file"
    else
      # shellcheck disable=SC2086
      screencapture -x $flags -l"$target" "$OUT/$file"
    fi
    echo "✓ $OUT/$file"
  else
    echo "✗ $scene did not report a window" >&2
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

for mode in light dark; do
  shoot popover "$mode" "lapse-popover-$mode.png"
  shoot settings-tracking "$mode" "lapse-settings-tracking-$mode.png"
  shoot settings-focus "$mode" "lapse-settings-focus-$mode.png"
  shoot settings-log "$mode" "lapse-settings-log-$mode.png"
  shoot settings-general "$mode" "lapse-settings-general-$mode.png"
  shoot onboarding-1 "$mode" "lapse-onboarding-$mode.png"
  shoot friction-countdown "$mode" "lapse-friction-countdown-$mode.png" -o
  shoot friction-reason "$mode" "lapse-friction-reason-$mode.png" -o
  shoot softblock "$mode" "lapse-limit-$mode.png" -o
done

# Menu bar labels are drawn straight to PNG by the app, no capture needed.
rm -rf "${DATA:?}"/*
LAPSE_DATA_DIR="$DATA" LAPSE_SCENE=menubar LAPSE_SCENE_OUT="$DATA/window" "$BIN" >/dev/null 2>&1 || true
for f in "$DATA"/menubar-*.png; do cp "$f" "$OUT/lapse-$(basename "$f")"; echo "✓ $OUT/lapse-$(basename "$f")"; done
