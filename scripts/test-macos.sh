#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/prepare-macos.sh"
bash "$ROOT/apps/macos/scripts/test.sh"
