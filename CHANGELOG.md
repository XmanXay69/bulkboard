# Changelog

## v0.2.0 · Body & Dunk, new look

### New
- **Body & Dunk** section. Check-ins with height, weight, wingspan, reach, wrist and tape measurements, jump numbers and an optional photo.
- **Proportion analysis**: each part vs a frame-scaled target (McCallum ratios, golden-ratio V-taper), Navy body-fat estimate, FFMI, and flagged focus areas.
- **AI photo review** with a local Ollama vision model (for example `llama3.2-vision`). The photo never leaves the Mac.
- **Focus areas** applied to the training plan: extra sets plus an accessory for lagging muscles, with an optional protein bump.
- **Dunk calculator**: reach estimate, required running jump, gap, inches lost per 10 lb at the same power, rough timeline, and a one-click jump program (depth jumps, trap-bar jumps, calf/ankle work, approach jumps on court days) with an optional 0.5 lb/week gain cap.

### Changed
- Redesigned UI: neutral surfaces, one accent color, system fonts, native controls, plain labels. Follows the system appearance by default.
- Toasts instead of confetti; XP and levels removed from the interface.
- New app icon.

### Data
- New check-in records migrate automatically from v0.1 stores. JSON backups now include check-ins, focus areas and the dunk goal (photos stay on disk).

## v0.1.0 · First release

The first public build of BulkBoard: a local-first Mac app for bulking while keeping your basketball conditioning.

### Highlights

- **Targets that show their math.** Mifflin-St Jeor TDEE, a surplus sized to your goal rate (with a warning when the date is unrealistic), protein/fat/carb split, and separate Practice Day / Game Day / Rest Day targets. Five goal modes, Bulk + Performance by default.
- **Auto-fill my week.** A meal planner that lands each day on its target from 80 built-in foods and 44 meals, with lock, shuffle, drag and drop, servings, allergy and dislike filters, and a meal-prep-to-variety slider. Shakes are shaker-bottle-only (no blender).
- **One-tap grocery list** merged across meals, grouped by aisle, with a phone-sized pop-out window, check-off, and copy/export as text.
- **YMCA-style training plan** for 0–6 lifting days plus court days, with leg days kept away from game days. Live logging with previous performance inline, overload suggestions, a rest timer, automatic PR detection, and confetti.
- **Basketball sessions** logged with session-RPE load, shown alongside lifting volume.
- **Progress:** bodyweight trend with a projection to your goal date, e1RM per lift, weekly volume, court load, calorie and protein adherence, streaks, XP, and a weekly box score.
- **Optional local AI** through Ollama on 127.0.0.1: meal ideas, macro estimates (always labeled), higher-protein swaps. Hidden when Ollama isn't running.
- **Your data stays on your Mac.** SwiftData store, daily automatic backups, JSON export/import, CSV export for logs. No accounts, no analytics, no cloud.
- Dark-first design with a light mode, scoreboard numerals, keyboard shortcuts for everything common, and a demo dataset you can wipe in one click.

### Install

Download `BulkBoard-0.1.0-macOS.zip`, unzip, and move BulkBoard.app to Applications. The build is ad-hoc signed, not notarized: on first launch go to System Settings → Privacy & Security → **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/BulkBoard.app`. Requires macOS 15+, universal (Apple silicon and Intel).

### Under the hood

- SwiftUI + SwiftData + Swift Charts, Swift 6.
- All calculation logic lives in the `BulkCore` package with 86 unit tests; 31 app tests cover the main flows against an in-memory store.
- CI on GitHub Actions (macOS 26) runs both suites and builds a universal Release app.
