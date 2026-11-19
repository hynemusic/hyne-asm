#!/bin/sh
# Packages the built app as a drag-to-Applications disk image plus its SHA-256 checksum.
#   scripts/make-dmg.sh "build/HYNE Ableton Shortcuts Manager.app" 1.2.3
#   → build/HYNE-ASM-1.2.3.dmg and build/HYNE-ASM-1.2.3.dmg.sha256
set -eu
cd "$(dirname "$0")/.."
APP="${1:?app path}"
VERSION="${2:?version}"
DMG="build/HYNE-ASM-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "HYNE ASM $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
(cd build && shasum -a 256 "HYNE-ASM-$VERSION.dmg" > "HYNE-ASM-$VERSION.dmg.sha256")
echo "$DMG"
