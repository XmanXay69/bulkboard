#!/bin/zsh
# Builds a universal, ad-hoc signed Release app and zips it into dist/.
# Usage: scripts/release.sh 0.1.0
set -euo pipefail
VERSION="${1:?version, e.g. 0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project BulkBoard.xcodeproj -scheme BulkBoard -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/release \
  MARKETING_VERSION="$VERSION" build | grep -E "error:|BUILD" || true
APP="build/release/Build/Products/Release/BulkBoard.app"
test -d "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/BulkBoard")"
codesign --verify --deep --strict "$APP" && echo "Signature OK (ad-hoc)"
mkdir -p dist
ZIP="dist/BulkBoard-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
