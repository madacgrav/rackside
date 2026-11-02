# TrainMe

![CI](https://github.com/madacgrav/trainme/actions/workflows/ci.yml/badge.svg)

TrainMe is a client and session log for independent personal trainers, on iPhone
and Apple Watch. Keep clients' goals, injuries, health screening, assessments and
waivers in one place; build reusable workouts; schedule and record sessions set by
set with a rest timer on your phone or wrist; and track each client's progress over
time. Everything stays on the iPhone — no account, no cloud, no tracking.

- **[User guide](https://madacgrav.github.io/trainme/guide/)** ([source](docs/guide/index.md))
- [Privacy policy](https://madacgrav.github.io/trainme/privacy/) · [Support](https://madacgrav.github.io/trainme/support/)
- [Changelog](CHANGELOG.md)
- License: [GPL v3](LICENSE)

For developers: product requirements in [PRD.md](PRD.md); roadmap and known gaps in
[BACKLOG.md](BACKLOG.md).

## Building

The Xcode project file is **generated, not committed**. The project is defined by
[`project.yml`](project.yml); [XcodeGen](https://github.com/yonaskolb/XcodeGen)
turns it into `Rackside.xcodeproj`.

After a fresh clone — or whenever files are added/removed outside Xcode — run:

```bash
brew install xcodegen   # first time only
xcodegen generate
open Rackside.xcodeproj
```

Then select the **Rackside** scheme, pick an iPhone simulator, and ⌘R.

### Command-line build & test

```bash
xcodegen generate
xcodebuild -scheme Rackside -destination 'platform=iOS Simulator,name=iPhone 17' test
```

If `xcodebuild` complains that it "requires Xcode" even though Xcode is installed,
either prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
or run once:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Requirements

- Xcode 26+ with the iOS 26 simulator runtime
- Deployment target: iOS 26

## Permissions

Notifications and calendar access are optional. Settings → Permissions shows the current
status of each and offers an **Open Settings** link when one has been denied. Session
reminders (24 h and 1 h before) are scheduled only while notifications are allowed;
"Add to calendar" on a session needs full calendar access and falls back to the first
writable calendar when no default is set.

Continuous integration runs `xcodegen generate` and the simulator test suite on every
pull request (`.github/workflows/ci.yml`).

## Project layout

- `Sources/Models/` — SwiftData `@Model` types and their Codable DTOs
- `Sources/Persistence/` — `@ModelActor` repositories, seed import, store backup
- `Sources/Services/` — notifications, messaging, EventKit calendar, PDF reports, export/import archive, app lock
- `Sources/Support/` — shared helpers (logging, formatters)
- `Sources/Support/Theme.swift` — color/font/spacing tokens (colorsets live in `Sources/Assets.xcassets`); `Sources/Features/Components/` — shared SwiftUI building blocks
- `Sources/Features/` — SwiftUI views + view models per feature (Schedule, Clients, Workouts, Exercises, Session, Reports, Settings)
- `Sources/AppIcon.icon/` — Icon Composer package (edit `icon.json`/`Assets/*.svg` as text, or open in Icon Composer); `Sources/Assets.xcassets/` holds `AccentColor`
- `Tests/` — Swift Testing suite (runs against in-memory containers); `Tests/Fixtures/export-v1.json` is the frozen export-format compatibility fixture — never regenerate it
- `Watch/` — Apple Watch app (rest timer mirror and quick start); `Shared/` — timer and sync code used by both apps
- `docs/` — GitHub Pages site: user guide, privacy policy, support, changelog; `docs/app-store/` — App Store submission kit and screenshots
- `scripts/` — `screenshots.sh` (regenerates App Store/guide screenshots from DEBUG demo data via `-demoData`), `sync-changelog.sh`, and doc checks
- `thoughts/qrspi/` — design/research/plan artifacts from the initial build
