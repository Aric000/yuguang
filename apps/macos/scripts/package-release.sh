#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage: bash scripts/package-release.sh v0.1.0}"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号必须为 v主版本.次版本.修订号，例如 v0.1.0" >&2
  exit 1
fi
ARCH="$(uname -m)"
APP="$PWD/dist/余光.app"
# Update version before signing and archiving so the app and Release agree.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION#v}" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist/release
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/yuguang-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/余光.app"
ln -s /Applications "$STAGING/Applications"
ASSET="Yuguang-${VERSION}-macOS-${ARCH}"
hdiutil create -volname "余光 ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "dist/release/${ASSET}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/release/${ASSET}.zip"
(cd dist/release && shasum -a 256 "${ASSET}.dmg" "${ASSET}.zip" > "${ASSET}.sha256")
echo "Release assets: dist/release/${ASSET}.{dmg,zip,sha256}"
