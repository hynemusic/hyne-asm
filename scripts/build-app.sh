#!/bin/sh
# Builds "build/HYNE Ableton Shortcuts Manager.app" and signs it with a stable identity.
#   HM_SIGN_IDENTITY="<identity>" [HM_VERSION=1.2.3] scripts/build-app.sh [--install]
# HM_VERSION sets the app's version (releases pass the tag's number). The app is universal (Apple Silicon + Intel).
# Never ad-hoc: an ad-hoc signature changes every build and macOS drops the Accessibility permission.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${HM_SIGN_IDENTITY:-}" ] || [ "$HM_SIGN_IDENTITY" = "-" ]; then
  echo "HM_SIGN_IDENTITY is not set (see README). Available identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS --product HMLauncherApp
BIN="$(swift build -c release $ARCHS --show-bin-path)/HMLauncherApp"
APP="build/HYNE Ableton Shortcuts Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HYNE ASM"
strip -x "$APP/Contents/MacOS/HYNE ASM"   # local symbols only needed for debugging: 6 MB → 2.4 MB
cp App/Info.plist "$APP/Contents/Info.plist"
if [ -n "${HM_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $HM_VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $HM_VERSION" "$APP/Contents/Info.plist"
fi
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
rsync -a --exclude __pycache__ --exclude '*.pyc' bridge/ASMbridge "$APP/Contents/Resources/"
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
