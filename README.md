<p align="center">
  <img src="docs/icon.png" width="128" alt="BulkBoard icon">
</p>

<h1 align="center">BulkBoard</h1>

<p align="center">
  <b>Eat big. Lift heavy. Keep your legs for the court.</b><br>
  A local-first Mac app for bulking while keeping your basketball conditioning: macros, meal plans, grocery lists, workouts and progress, in one place.
</p>

<p align="center">
  <a href="https://github.com/XmanXay69/bulkboard/actions/workflows/ci.yml"><img src="https://github.com/XmanXay69/bulkboard/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-0A1020" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F07A2A" alt="Swift 6">
  <img src="https://img.shields.io/badge/data-100%25%20local-2FC48D" alt="Local only">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

![Dashboard](docs/screenshots/dashboard.png)

## What it does

1. **Sets your calorie and macro targets** from your stats and goal, and shows the math.
2. **Builds a weekly meal plan** that hits those targets, from a built-in food list or your own recipes.
3. **Generates the grocery list** from the plan, merged and grouped by aisle.
4. **Gives you a weekly training plan**: a lifting split for a standard gym (the YMCA kind) plus basketball conditioning days.
5. **Logs bodyweight, lifts and court sessions** and shows progress, PRs and streaks.

No account, no cloud, no analytics. Your data stays on your Mac.

## Features

### Targets that show their work
- Mifflin-St Jeor BMR × activity level for maintenance, then a surplus sized to your target rate of gain (default 0.5–1 lb/week).
- Warns when a goal date is unrealistic, caps the rate, and tells you when you'll actually get there.
- Protein from bodyweight (0.8–1 g/lb), fat as a share of calories (25–30%), carbs fill the rest.
- Separate targets for **Practice Day** (lifting), **Game Day** (court conditioning, more carbs) and **Rest Day**, averaging out to your weekly target. Override any of them.
- Five goal modes: Bulk, **Bulk + Performance** (default), Recomp, Cut, Maintain.

![Targets and the math](docs/screenshots/targets.png)

### Meal planner
- 7-day grid with breakfast, lunch, snacks, dinner and shakes; running totals per day with over/under indicators.
- **Auto-fill my week** proposes meals that land each day on its day-type target. **Shuffle** re-rolls anything unlocked; **lock** meals you like.
- Click a slot to pick a meal, or drag from the meal library. Right-click for servings, swap, lock, or mark eaten.
- Respects allergies and dislikes. A **variety** setting goes from *Meal prep* (repeat a few meals, short grocery list) to *Mix it up*.
- 80 built-in foods, 44 meals, and **shaker-bottle-only shakes** (no blender: powders and liquids only, enforced by tests). An editable whey scoop is pre-seeded under *My foods*.

![Meal plan](docs/screenshots/meal-plan.png)

### Grocery list
- One tap builds it from the week's plan. Quantities merge across meals with unit conversion and group by store section.
- Check-off mode, a phone-sized **pop-out window** for the store, manual items, copy or export as plain text.

![Grocery list](docs/screenshots/grocery.png)

### Training
- Weekly plan generator for 0–6 lifting days plus court days, arranged so leg days don't land right before game days. *Bulk + Performance* adds plyos and med-ball work.
- Live logger with **previous performance inline**, **progressive overload suggestions** ("Last time 135 × 8 lb. Try 140 today."), a rest timer with a chime, and **automatic PR detection** (heaviest weight, best e1RM, rep PRs) with a confetti moment.
- Log basketball sessions (pickup, league, drills, conditioning) with duration and RPE; load shows up next to lifting volume.
- 54-exercise library for barbells, dumbbells, machines and cables, plus your own custom exercises.

| This week | Logging a session |
|---|---|
| ![Training week](docs/screenshots/training-week.png) | ![Workout logger](docs/screenshots/training-log.png) |

### Progress
- Bodyweight with a 7-day moving average and a projection toward your goal date.
- Estimated 1RM per lift, weekly lifting volume, court load, calorie and protein adherence.
- Streaks, XP and levels, plus a weekly **box score** (this week vs last).

<img src="docs/screenshots/progress.png" alt="Progress" width="720">

### Optional local AI
If [Ollama](https://ollama.com) is running on your Mac, BulkBoard adds an **Ask the coach** helper for meal ideas, macro estimates for anything you type, and higher-protein swaps. It talks only to `127.0.0.1:11434`. No cloud APIs, no keys. AI numbers are always labeled as estimates. Without Ollama, these controls just hide.

### Looks
Dark by default (light and system modes too): scoreboard numerals, hardwood-orange accents, court-line art, XP bars, and a little fanfare when you hit a PR or finish your day's macros.

| Welcome | Light mode |
|---|---|
| ![Welcome](docs/screenshots/welcome.png) | ![Light mode](docs/screenshots/dashboard-light.png) |

## Install

1. Download `BulkBoard-0.1.0-macOS.zip` from the [latest release](https://github.com/XmanXay69/bulkboard/releases/latest) and unzip it.
2. Drag **BulkBoard.app** to Applications.
3. The build is ad-hoc signed, not notarized, so macOS will block the first launch. Either:
   - open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run this once:

```bash
xattr -dr com.apple.quarantine /Applications/BulkBoard.app
```

Requires macOS 15 Sequoia or later, Apple silicon or Intel (universal build).

## Build from source

Requires Xcode 26 or later.

```bash
git clone https://github.com/XmanXay69/bulkboard.git
```

```bash
cd bulkboard && open BulkBoard.xcodeproj
```

Press ⌘R. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you only need XcodeGen when you add or move files (`brew install xcodegen && xcodegen generate`).

Run all tests:

```bash
scripts/test.sh
```

To try it without entering your own stats, click **Explore with demo data** on the welcome screen. Demo records carry a DEMO badge and can be wiped from Settings → Data.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 – ⌘7 | Dashboard, Meal Plan, Grocery, Training, Progress, Targets, Foods & Recipes |
| ⇧⌘F | Auto-fill the week |
| ⇧⌘R | Shuffle unlocked meals |
| ⇧⌘G | Build grocery list |
| ⌘[ / ⌘] / ⇧⌘T | Previous / next / this week |
| ⇧⌘W | Log weigh-in |
| ⇧⌘E | Quick add food |
| ⇧⌘L | Start today's workout |
| ⇧⌘B | Log basketball session |
| ⇧⌘A | Ask the coach (with Ollama) |
| ⇧⌘S | Export backup |
| ⇧⌘C | Copy grocery list as text |

## Your data

- Stored with SwiftData in `~/Library/Application Support/BulkBoard/`.
- **Automatic daily backups** (last 14 kept) to `…/BulkBoard/Backups` or a folder you pick.
- **Export / import** a full JSON backup, and export CSVs for weigh-ins, lifts, court sessions and intake (File menu or Settings → Data).
- The only network connection BulkBoard ever makes is to Ollama on `127.0.0.1`, and only if you enable it.

## Tech stack

- **SwiftUI + SwiftData + Swift Charts**, Swift 6 strict concurrency, macOS 15+.
- **BulkCore**, a pure Swift package with no UI and no persistence, holds all the math: TDEE, gain-rate planning, macro splits, meal auto-fill, grocery merging, the split generator, PR detection, overload suggestions, trend/projection, streaks, XP. It's covered by 86 unit tests (`swift test`).
- The app target maps SwiftData records to BulkCore value types. 31 app tests cover onboarding, planning, groceries, training, progress, demo data and backups against an in-memory store.
- Built-in foods, meals and exercises ship as JSON in `Packages/BulkCore/Sources/BulkCore/Resources`. Tests check every food's calories against its macros, every recipe's ingredients, and that every shake is shaker-safe.

```
BulkBoard/
├── Packages/BulkCore/        # calculation logic + seed data + tests (swift test)
├── BulkBoard/
│   ├── App/                  # app entry, root/sidebar, menu commands
│   ├── Models/               # SwiftData records, persistence, record ↔ core mapping
│   ├── Services/             # meal plan, grocery, training, progress, backup, Ollama, demo data
│   ├── Features/             # Dashboard, Meals, Grocery, Training, Progress, Targets, Library, Settings, Onboarding
│   ├── Design/               # theme tokens, components, charts, celebrations, icon mark
│   └── Debug/                # launch-argument screenshot capture
├── BulkBoardTests/           # app-level tests (in-memory store)
├── scripts/                  # test, capture, screenshots, icon, release
└── project.yml               # XcodeGen spec
```

## Roadmap

- [ ] Barcode / label scanning via Continuity Camera
- [ ] iPhone companion for logging sets and groceries at the gym (CloudKit sync, opt-in)
- [ ] Plate calculator and warm-up set generator
- [ ] Deload weeks and periodization blocks
- [ ] Edit the generated split (swap exercises, reorder days)
- [ ] Apple Health export for weight and workouts
- [ ] Recipe import from a URL (local parsing, no cloud)
- [ ] Notarized builds

## Contributing

Issues and PRs are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Adding foods or meals is a great first PR: edit the JSON and the tests tell you if anything's off.

## Disclaimer

BulkBoard does arithmetic on standard formulas. It isn't medical or dietary advice. Talk to a professional if you have health conditions, and listen to your body.

## License

[MIT](LICENSE) © 2026 Xay
