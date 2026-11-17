#!/bin/sh
# Builds "build/HYNE Ableton Shortcuts Manager.app" and signs it with a stable identity.
#   HM_SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh [--install]
# Never ad-hoc: an ad-hoc signature changes every build and macOS drops the Accessibility permission.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${HM_SIGN_IDENTITY:-}" ] || [ "$HM_SIGN_IDENTITY" = "-" ]; then
  echo "HM_SIGN_IDENTITY is not set (see README). Available identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

swift build -c release --product HMLauncherApp
BIN="$(swift build -c release --show-bin-path)/HMLauncherApp"
APP="build/HYNE Ableton Shortcuts Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HYNE ASM"
cp App/Info.plist "$APP/Contents/Info.plist"
rsync -a --exclude __pycache__ --exclude '*.pyc' bridge/HMLauncherBridge "$APP/Contents/Resources/"
codesign --force --sign "$HM_SIGN_IDENTITY" --identifier local.hm.launcher "$APP"
codesign --verify --verbose=1 "$APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x "HYNE ASM" || true
  pkill -x "HM Launcher" || true          # old name
  rm -rf "/Applications/HM Launcher.app"  # old name
  rm -rf "/Applications/HYNE Ableton Shortcuts Manager.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/HYNE Ableton Shortcuts Manager.app"
fi
