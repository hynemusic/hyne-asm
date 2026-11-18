#!/bin/sh
# Developer aid: renders every settings page to PNGs. Usage: scripts/snapshot-settings.sh <out-dir>
set -eu
cd "$(dirname "$0")/.."
OUT="${1:?out dir}"
mkdir -p "$OUT"
swift build --product HMLauncherApp >/dev/null
BIN="$(swift build --show-bin-path)/HMLauncherApp"
for page in 0 2 3 1; do
  HM_SETTINGS_PAGE=$page HM_SNAPSHOT="$OUT/page-$page.png" "$BIN" >/dev/null 2>&1 || true
done
ls "$OUT"
