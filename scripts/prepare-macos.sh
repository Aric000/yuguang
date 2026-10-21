#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/apps/macos/Sources/Yuguang/Resources/Teams"
mkdir -p "$TARGET"
rsync -a --delete "$ROOT/shared/assets/teams/" "$TARGET/"
cp "$ROOT/shared/assets/AppIcon.icns" "$ROOT/apps/macos/scripts/AppIcon.icns"
