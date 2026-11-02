# Research Questions

## Context
Focus on the TrainMe iOS app (`Sources/`), the watchOS app (`Watch/`, `Shared/`), the XcodeGen spec (`project.yml`), Info.plist / entitlements / privacy manifest, the existing markdown docs (`README.md`, `PRD.md`, `BACKLOG.md`, `thoughts/qrspi/*`), SwiftUI previews and preview fixtures, and git history (merged PRs, commits).

## Questions
1. Starting from `RootView` and `Watch/TrainMeWatchApp.swift`, what are the user-facing screens and flows (each tab, the screens reachable from them, sheets, the lock gate, intake, session run, reports, timers, watch quick start), and what actions can a user perform on each?

2. What first-run and empty-state behavior exists — what data is seeded on first launch (`SeedImporter`, `seed_exercises.json`, `waiver_starter.txt`), what do screens show when there is no data, and what in-app help, captions, or explanatory text already exists?

3. How are the app's version number, build number, display name, bundle IDs, deployment targets, supported devices/orientations, and app icon defined across `project.yml`, `Sources/Info.plist`, the generated project, and `Sources/AppIcon.icon`, and is any of it read at runtime (e.g. `DataArchive`, Settings/About)?

4. What system permissions, data collection, storage, and data-sharing behavior does the app have — usage-description strings, `PrivacyInfo.xcprivacy` contents, entitlements, Face ID, calendar, notifications, Messages, WatchConnectivity, PDF/report export and data archive import/export — and where does user data live and leave the device?

5. What mechanisms exist for rendering the app with representative data outside of normal use — `#Preview` blocks, `PreviewFixtures`, test fixtures, launch arguments or debug flags, schemes, CI steps (`.github/workflows/ci.yml`) — and how were the existing images in `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/` produced (naming, sizes, light/dark/accessibility variants)?

6. What is the chronological history of user-visible changes in the repository — for each merged PR (#1 through #42) and its corresponding `thoughts/qrspi/*` directory, what features, fixes, and schema changes (SchemaV1→V3) landed, and on what dates?

7. What existing documentation describes the product and its intended users (`README.md`, `PRD.md`, `BACKLOG.md`, `LICENSE`), and what does each currently say about features, audience, support, and licensing?
