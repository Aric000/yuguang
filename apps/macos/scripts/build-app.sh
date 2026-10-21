#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/余光.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Yuguang" "$APP/Contents/MacOS/Yuguang.new"
mv -f "$APP/Contents/MacOS/Yuguang.new" "$APP/Contents/MacOS/Yuguang"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f scripts/AppIcon.icns ]; then cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
if [ -d "$BIN_DIR/Yuguang_Yuguang.bundle" ]; then
  ditto "$BIN_DIR/Yuguang_Yuguang.bundle" "$APP/Contents/Resources/Yuguang_Yuguang.bundle"
fi
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Yuguang-macOS.zip"
echo "应用已生成：$APP"
