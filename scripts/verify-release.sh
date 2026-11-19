#!/bin/sh
# Checks a built app before it is released. Fails (exit 1) unless:
#   - the tag looks like vX.Y.Z and the app's version is X.Y.Z,
#   - the app is signed by exactly the project's "HYNE ASM" certificate (pinned by fingerprint: a new certificate
#     with the same name would make every user lose the Accessibility permission),
#   - the app runs on Apple Silicon and Intel.
#   scripts/verify-release.sh "build/HYNE Ableton Shortcuts Manager.app" v1.2.3
set -eu
APP="${1:?app path}"
TAG="${2:?tag}"
CERT_SHA1="1522e1ab3fcffe7da02402f3456cd2f7154bc0b6"

fail() { echo "verify-release: $*" >&2; exit 1; }

echo "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "tag '$TAG' is not vX.Y.Z"
VERSION="${TAG#v}"

codesign --verify --strict "$APP" || fail "signature is not valid"
codesign -d -r- "$APP" 2>&1 | grep -q "certificate leaf = H\"$CERT_SHA1\"" \
  || fail "not signed with the HYNE ASM certificate ($CERT_SHA1)"

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$PLIST_VERSION" = "$VERSION" ] || fail "app version $PLIST_VERSION does not match tag $TAG"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/HYNE ASM")"
case " $ARCHS " in
  *" arm64 "*) ;;
  *) fail "no arm64 slice ($ARCHS)" ;;
esac
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) fail "no x86_64 slice ($ARCHS)" ;;
esac

echo "verify-release: OK ($TAG, HYNE ASM, $ARCHS)"
