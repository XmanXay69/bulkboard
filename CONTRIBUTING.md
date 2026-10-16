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
| Persistence or record fields | `BulkBoard/Models`. Only add fields, with defaults, so stores migrate in place; test against an old store with `--store=` |
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

`scripts/screenshots.sh` rebuilds everything in `docs/screenshots` from fictional sample data (`Debug/SampleData.swift`, compiled into Debug builds only), using the app's built-in capture mode (no Screen Recording permission needed). Build the Debug app first. The Log a meal shot looks up real products, so it needs a connection.

## Releases

`scripts/release.sh <version>` builds the universal Release app and writes `dist/BulkBoard-<version>.dmg` (drag-to-install) and `dist/BulkBoard-<version>-macOS.zip`. Bump `MARKETING_VERSION` in `project.yml` first, tag `v<version>`, then attach both files to the GitHub release. CI also uploads a DMG artifact for every push.

The in-app updater installs the `BulkBoard-<version>-macOS.zip` asset from the latest (non-pre-release) GitHub release, so keep that file name. To test an update end to end without publishing, serve a GitHub-style `latest.json` and the zip locally and launch an older build with `--store=<scratch>/BulkBoard.store --update-feed=http://127.0.0.1:<port>/latest.json --update-auto` (add `--update-test-apps=<folder>` to stand in for /Applications). Those switches only work together with `--update-feed`, and test runs keep their backups and photos next to the scratch store.

## Pull requests

- Small and focused. Describe what changed and how you tested it.
- `scripts/test.sh` is green.
- No personal data, secrets, or build output in commits.
- UI changes: include a before/after screenshot.

By contributing you agree your work is released under the MIT license.
