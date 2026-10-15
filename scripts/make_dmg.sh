#!/bin/zsh
# Packages BulkBoard.app into a drag-to-install DMG.
# Usage: scripts/make_dmg.sh <path/to/BulkBoard.app> <version> [out-dir]
set -euo pipefail
APP="${1:?path to BulkBoard.app}"
VERSION="${2:?version, e.g. 0.2.0}"
OUT_DIR="${3:-dist}"
test -d "$APP"
mkdir -p "$OUT_DIR"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/BulkBoard.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open.txt" <<'TXT'
1. Drag BulkBoard into Applications.
2. Open it. macOS blocks the first launch because this build isn't notarized by Apple.
3. Go to System Settings > Privacy & Security and click "Open Anyway".

Or run this once in Terminal:
xattr -dr com.apple.quarantine /Applications/BulkBoard.app

BulkBoard keeps all data on your Mac. Source: https://github.com/XmanXay69/bulkboard
TXT

DMG="$OUT_DIR/BulkBoard-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "BulkBoard $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "DMG verified: $DMG"
shasum -a 256 "$DMG"
