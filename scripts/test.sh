#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_DIR_PATH="$(xcode-select -p)"
MACRO_LIBRARY="$DEVELOPER_DIR_PATH/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
# The standalone macOS CLT includes Swift Testing, but some releases omit automatic macro discovery.
if [ -f "$MACRO_LIBRARY" ]; then
  swift test --disable-xctest -Xswiftc -warnings-as-errors -Xswiftc -load-plugin-library -Xswiftc "$MACRO_LIBRARY"
else
  swift test --disable-xctest -Xswiftc -warnings-as-errors
fi
