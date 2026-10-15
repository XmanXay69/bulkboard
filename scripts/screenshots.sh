#!/bin/zsh
# Regenerates the README screenshots in docs/screenshots from demo data.
# Requires a Debug build: xcodebuild -scheme BulkBoard -derivedDataPath build build
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/screenshots"
TMP="$(mktemp -d)"
mkdir -p "$OUT"

"$ROOT/scripts/capture.sh" "$TMP/main" --demo --appearance=dark --sections=dashboard,meals,grocery,training,body,targets,library >/dev/null
"$ROOT/scripts/capture.sh" "$TMP/progress" --demo --appearance=dark --sections=progress --full-page >/dev/null
"$ROOT/scripts/capture.sh" "$TMP/onboarding" --onboarding --appearance=dark >/dev/null
"$ROOT/scripts/capture.sh" "$TMP/light" --demo --sections=dashboard --appearance=light >/dev/null

cp "$TMP/main/01-dashboard.png" "$OUT/dashboard.png"
cp "$TMP/main/02-meals.png" "$OUT/meal-plan.png"
cp "$TMP/main/03-grocery.png" "$OUT/grocery.png"
cp "$TMP/main/04-training-this-week.png" "$OUT/training-week.png"
cp "$TMP/main/04-training-log.png" "$OUT/training-log.png"
cp "$TMP/main/05-body-physique.png" "$OUT/body-physique.png"
cp "$TMP/main/05-body-dunk.png" "$OUT/body-dunk.png"
cp "$TMP/main/06-targets.png" "$OUT/targets.png"
cp "$TMP/main/07-library.png" "$OUT/library.png"
cp "$TMP/progress/01-progress.png" "$OUT/progress.png"
cp "$TMP/onboarding/onboarding-0-welcome.png" "$OUT/welcome.png"
cp "$TMP/onboarding/onboarding-5-results.png" "$OUT/onboarding-targets.png"
cp "$TMP/light/01-dashboard.png" "$OUT/dashboard-light.png"
rm -rf "$TMP"
ls -1 "$OUT"
