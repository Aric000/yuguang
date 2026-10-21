#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/prepare-macos.sh"
bash "$ROOT/apps/macos/scripts/build-app.sh"
VERSION="${1:-0.2.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Invalid version' >&2; exit 1; fi
APP="$ROOT/apps/macos/dist/余光.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/release"
ARCH="$(uname -m)"
ASSET="Yuguang-${VERSION}-macOS-${ARCH}"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/release/${ASSET}.zip"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/yuguang-native.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/余光.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "余光 $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/release/${ASSET}.dmg"
(cd "$ROOT/release" && shasum -a 256 "${ASSET}.zip" "${ASSET}.dmg" > "${ASSET}.sha256")
