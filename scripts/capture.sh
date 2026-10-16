#!/bin/zsh
# Renders app screens to PNGs using the built-in capture mode.
# Usage: scripts/capture.sh <out-dir> [extra args...]   e.g. scripts/capture.sh docs/screenshots --sample
set -euo pipefail
OUT="${1:?output dir}"; shift
APP="$(cd "$(dirname "$0")/.." && pwd)/build/Build/Products/Debug/BulkBoard.app"
OUT="$(mkdir -p "$OUT" && cd "$OUT" && pwd)"
find "$OUT" -name "*.png" -delete
open -n -W "$APP" --args -ApplePersistenceIgnoreState YES --in-memory --capture="$OUT" --quit "$@"
ls "$OUT"
