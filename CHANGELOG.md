# Changelog

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
