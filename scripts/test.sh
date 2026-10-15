#!/bin/zsh
# Runs the BulkCore logic tests and the app tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "▶ BulkCore (swift test)"
(cd "$ROOT/Packages/BulkCore" && swift test 2>&1 | grep -E "✘|error:|Test run with")
echo "▶ App (xcodebuild test)"
(cd "$ROOT" && xcodegen generate --quiet && xcodebuild -project BulkBoard.xcodeproj -scheme BulkBoard \
  -derivedDataPath build -destination 'platform=macOS' test 2>&1 | grep -E "✘|error:|Test run with|TEST (SUCCEEDED|FAILED)")
