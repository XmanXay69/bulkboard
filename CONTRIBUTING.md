# Contributing to BulkBoard

Thanks for helping out. BulkBoard is a small, local-first Mac app, so the bar is: keep it fast, private, and easy to read.

## Setup

- Xcode 26+, macOS 15+.
- `open BulkBoard.xcodeproj` and press ⌘R.
- If you add, move or delete source files, regenerate the project: `brew install xcodegen && xcodegen generate`. CI fails if `BulkBoard.xcodeproj` is out of sync with `project.yml`.

## Where things go

| You're changing… | Put it in… |
|---|---|
| Any math (energy, macros, planner, grocery merge, PRs, trends) | `Packages/BulkCore`, with tests |
| Built-in foods, meals, exercises | `Packages/BulkCore/Sources/BulkCore/Resources/*.json` |
| Persistence or record fields | `BulkBoard/Models` (bump the schema version if you change a record) |
| Actions that touch the store | `BulkBoard/Services` |
| Screens | `BulkBoard/Features/<Screen>` |
| Colors, type, shared components | `BulkBoard/Design` |

Keep logic out of views. If it can be a pure function on BulkCore value types, it should be, and it should have a test.

## Tests

```bash
scripts/test.sh
```

That runs `swift test` for BulkCore and `xcodebuild test` for the app. New logic needs unit tests, and new flows should get an app test against an in-memory store (see `BulkBoardTests/`).

## Adding foods and meals

- Foods: per-serving macros, a `serving` label people recognize, and an `amount` + `unit` that a grocery list can add up (grams for dry goods, `piece` for things you buy whole).
- Calories should match 4/4/9 within ~10% (20% for produce and snacks, because of fiber). The tests check this.
- Shakes may only use foods with `"shaker": true`: powders and liquids that mix in a shaker bottle with no blender.
- Keys are permanent. Don't rename a key once it has shipped; IDs are derived from it.

## Design notes

- Keep it quiet: neutral surfaces, one accent (`Theme.accent`), system fonts, native controls. Every color is a token in `Design/Theme.swift` with light and dark values.
- Charts plot a single measure in the accent color (`Design/ChartStyle.swift`). Don't put two measures with different units on one axis; use two charts.
- Green and red are reserved for on-target/over and always come with an icon or label.

## Screenshots

`scripts/screenshots.sh` rebuilds everything in `docs/screenshots` from demo data, using the app's built-in capture mode (no Screen Recording permission needed). Build the Debug app first.

## Pull requests

- Small and focused. Describe what changed and how you tested it.
- `scripts/test.sh` is green.
- No personal data, secrets, or build output in commits.
- UI changes: include a before/after screenshot.

By contributing you agree your work is released under the MIT license.
