# Structure Outline

## Approach
Make the app release-ready first (one version source, iPhone-only, category, encryption flag, changelog). Then publish the required public pages (privacy and support), wire the in-app About section to them, and add a debug-only demo mode so screenshots can be reproduced. Finish with the user guide and the App Store submission kit built on those screenshots. Each phase ships something usable even if later phases stall.

## Phase 1: Version source and changelog
Both targets read one version from `project.yml`. The app is declared iPhone-only and Health & Fitness, with no export-compliance prompt. The full history goes in `CHANGELOG.md` as 0.1.0–0.6.0, with 1.0.0 under `[Unreleased]`.

**Files**:
- `project.yml`
- `Sources/Info.plist`
- `CHANGELOG.md` (new)
- `Tests/AppVersionTests.swift` (new)
- `BACKLOG.md` (row 34 moved to Done)

**Key changes**:
- `project.yml` `settings.base`: `MARKETING_VERSION: "1.0.0"` and `CURRENT_PROJECT_VERSION: "1"`, removed from the TrainMeWatch target.
- TrainMe target: `TARGETED_DEVICE_FAMILY: "1"`.
- `Info.plist`:
  - `CFBundleShortVersionString = $(MARKETING_VERSION)`
  - `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
  - `LSApplicationCategoryType = public.app-category.healthcare-fitness`
  - `ITSAppUsesNonExemptEncryption = false`
- `CHANGELOG.md`: Keep a Changelog sections (Added/Changed/Fixed). The `[Unreleased] — 1.0.0` entry is followed by 0.6.0 down to 0.1.0, with dates and PR links from research Q6, plus compare links that need tags.
- Git tags `v0.1.0` (`293f8c1`), `v0.2.0` (`6344ac6`), `v0.3.0` (`0c7a624`), `v0.4.0` (`d47fea0`), `v0.5.0` (`2b593fd`) and `v0.6.0` (`cc709b8`), created **locally only**. The owner pushes them.

**Verify**:
- `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' test` passes, and the TrainMeWatch build passes.
- `plutil -p` on the built `.app` and watch `.app` shows `1.0.0 (1)` for both, plus `UIDeviceFamily = [1]`.
- Test: `AppVersionTests` asserts that `Bundle.main` `CFBundleShortVersionString` matches the `^\d+\.\d+\.\d+$` pattern (no literal `1.0`).

---

## Phase 2: Public docs site (privacy, support, changelog)
Publishes the two URLs App Store Connect requires, plus the changelog, as a Jekyll site in `docs/` for GitHub Pages (main branch, `/docs`).

**Files**:
- `docs/_config.yml`
- `docs/index.md`
- `docs/privacy.md`
- `docs/support.md`
- `docs/changelog.md` (includes the root CHANGELOG via front matter, or a short page linking to it)
- `scripts/check-docs-links.sh` (new)

**Key changes**:
- `_config.yml`: `title: TrainMe`, `theme: jekyll-theme-primer` (supported by Pages), `baseurl: /trainme`.
- Stable URLs: `/trainme/privacy/`, `/trainme/support/`, `/trainme/guide/`, `/trainme/changelog/`. The URL map is fixed here because Phase 3 hard-codes it.
- Privacy policy content comes from research Q4 and design decision 8. Support content: email, GitHub issues, and an FAQ (data is on-device only, reinstalling needs an export file, Face ID, the recovery screen).

**Verify**: `scripts/check-docs-links.sh` (a grep-based check that relative links resolve to files) exits 0. Manually, review the markdown rendering in the repo. Live Pages verification happens after the owner enables Pages (checklist).

---

## Phase 3: In-app About section
The last section in Settings shows the version and build, plus links to the Phase 2 URLs and the license.

**Files**:
- `Sources/Support/AppInfo.swift` (new)
- `Sources/Features/Settings/SettingsView.swift`
- `Tests/AppInfoTests.swift` (new)

**Key changes**:
- `enum AppInfo { static func versionString(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String }` returns `"1.0.0 (1)"`.
- `enum AppLinks { static let guide, privacy, support, changelog, license: URL }`, with base `https://madacgrav.github.io/trainme/`. The license URL points to the GitHub `LICENSE` file.
- `SettingsView`: `Section("About")` holds `LabeledContent("Version", value: AppInfo.versionString())` and five `Link` rows, following the existing `PermissionRow`/`Link` pattern (`SettingsView.swift:225-239`).
- `DataArchive.swift:46` stays as is. It now reads `1.0.0` through the plist build setting.

**Verify**:
- Unit tests: `AppInfoTests` covers present, missing and partial info dictionaries. The existing `ArchiveRoundTripTests` still pass.
- Manual: in the simulator, Settings › About shows `1.0.0 (1)` and the links open Safari.

---

## Phase 4: iPhone demo mode (DEBUG only)
Launching with `-demoData` starts the app unlocked on a realistic in-memory dataset. `-demoScreen <name>` opens a chosen screen directly.

**Files**:
- `Sources/Support/DemoLaunch.swift` (new, whole file `#if DEBUG`)
- `Sources/Support/DemoData.swift` (new, `#if DEBUG`)
- `Sources/TrainMeApp.swift`
- `Sources/Features/Lock/LockGateView.swift`
- `Sources/RootView.swift`
- small optional `initialRoute` hooks in `ClientListView` and `ScheduleView`
- `Tests/DemoDataTests.swift`

**Key changes**:
- `struct DemoLaunch { let enabled: Bool; let screen: DemoScreen?; init(arguments: [String] = ProcessInfo.processInfo.arguments) }`.
- `enum DemoScreen: String { case schedule, scheduleWeek, session, clients, client, report, exerciseReport, assessment, workouts, builder, exercises, settings }`.
- `enum DemoData { static func container(now: Date = .now) throws -> ModelContainer }`. It reuses the `PreviewFixtures` DTO → `toModel()` insert path, expanded to:
  - about 6 clients, including a self client
  - a week of sessions with mixed statuses
  - about 8 weeks of completed history with sets, so the charts render
  - two assessments, one screening and one signed waiver
  - about 4 workout templates
  - the seed exercise library
- `AppBootstrap.init(demo: DemoLaunch)`: when enabled, `state = .ready(try DemoData.container())`. No disk store is touched, and the backup step is skipped.
- `LockGateView`: `#if DEBUG` auto-unlocks when demo is enabled.
- `RootView`: `init(container:, initialTab: Int = 0, demoScreen: DemoScreen? = nil)`. Demo mode also suppresses the first-run backup alert and the export banner. Deep screens get a `NavigationPath`/`@State` initial value passed in. If a route turns out to be invasive, it drops to "tab only" and the shot is taken manually (Open Risk).
- Release builds have no demo symbols. Every demo reference sits behind `#if DEBUG`.

**Verify**:
- `DemoDataTests`: container counts (clients ≥ 5, completed sessions ≥ 10, and so on), and `DemoLaunch(arguments:)` parsing.
- `xcodebuild -configuration Release build` succeeds, and `nm`/`strings` on the binary shows no `DemoData`.
- Manual: `xcrun simctl launch booted com.madacgrav.trainme -demoData -demoScreen report` opens the populated report.

---

## Phase 5: Watch demo mode and watch App Store readiness
The watch shows a running or idle timer with no phone attached. The watch target gets the app icon and, if it needs one, a privacy manifest.

**Files**:
- `Watch/TrainMeWatchApp.swift`
- `Watch/WatchDemo.swift` (new, `#if DEBUG`)
- `project.yml` (watch icon source and settings)
- `Watch/PrivacyInfo.xcprivacy` (new, only if UserDefaults or another required-reason API is used in Watch/Shared)

**Key changes**:
- `enum WatchDemo { static func snapshot(state: String, now: Date) -> TimerSnapshot }` with states `running` (Rest, 90 s, about 60 s left) and `idle` (up next "Goblet Squat · 45 s").
- `TrainMeWatchApp`: `-demoData [-demoWatch running|idle]` gives `WatchTimerModel(snapshot:)` and skips `activate()`.
- Watch target: add `Sources/AppIcon.icon` as a resource and set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.

**Verify**:
- The watch build succeeds, and the icon appears in the watch simulator.
- Manual: launching the watch sim with the args shows each state.
- `grep -r UserDefaults Watch Shared` decides whether the manifest is needed.

---

## Phase 6: Screenshot script and App Store screenshots
One command produces every App Store image and every guide image.

**Files**:
- `scripts/screenshots.sh` (new)
- `docs/app-store/screenshots/*.png`
- `docs/guide/images/*.png`

**Key changes**:
- `screenshots.sh [--dark] [--only <screen>]` does the following:
  1. Builds the Debug app for the simulator.
  2. Boots `iPhone 17 Pro Max` (6.9", 1320×2868) and an Apple Watch Ultra simulator (falling back to whichever is listed).
  3. Sets the status bar override (`simctl status_bar override --time 9:41 --batteryLevel 100`).
  4. For each `DemoScreen`, launches with the demo args, sleeps, and captures.
- App Store set: 6 iPhone shots (`01-schedule-week`, `02-session-timer`, `03-client-detail`, `04-report`, `05-assessment`, `06-builder`) and 2 watch shots (`w1-running`, `w2-idle`).

**Verify**: the script exits 0. `sips -g pixelWidth -g pixelHeight` confirms 1320×2868 for iPhone and the watch native size. Manually review each image (populated data, no alerts, 9:41 status bar).

---

## Phase 7: User guide and README
The full how-to guide on the docs site, with screenshots. The README points users to it.

**Files**:
- `docs/guide/index.md`, with one page per topic: `getting-started`, `clients-and-intake`, `health-assessments-waivers`, `workouts-and-exercises`, `scheduling`, `running-a-session`, `apple-watch`, `reports`, `backup-and-restore`, `settings`, `troubleshooting`
- `README.md`

**Key changes**: screen names and button labels quoted exactly from research Q1. Every page has ≥ 1 image from Phase 6. The README gets a product paragraph and links to the guide, privacy, support, changelog and license, and mentions the watch app.

**Verify**: `scripts/check-docs-links.sh` passes, which checks images and cross-links. A label spot-check script greps each quoted label (in backticks) in the guide against `Sources/` and `Watch/` and reports any that are missing.

---

## Phase 8: App Store submission kit
Everything to paste into App Store Connect, plus the owner's manual steps.

**Files**:
- `docs/app-store/metadata.md`
- `docs/app-store/whats-new/1.0.0.md`
- `docs/app-store/checklist.md`
- `scripts/check-metadata-lengths.sh`
- `docs/_config.yml` (exclude `app-store/` from the published nav)

**Key changes**:
- `metadata.md` has fenced blocks per field: name (≤30), subtitle (≤30), promo (≤170), description (≤4000), keywords (≤100, comma-separated), category, price $0.99, age rating answers, URLs, copyright, review notes, App Privacy "Data Not Collected", and screenshot captions.
- `checklist.md` lists the owner's steps:
  - enable Pages
  - push tags
  - Paid Apps Agreement, tax and banking
  - create the app record
  - set the price
  - archive and upload
  - fill in the metadata
  - answer the privacy questions
  - decide on the GPL vs App Store licence question
  - set the legal name for the copyright

**Verify**: `scripts/check-metadata-lengths.sh` extracts each fenced field and fails on any over its limit. Manually read the listing end to end.

## Testing Checkpoints
| After | True |
|---|---|
| P1 | Both apps build as 1.0.0 (1), iPhone-only, Health & Fitness category, no encryption prompt. CHANGELOG lists 0.1.0–1.0.0. Tags exist locally. Tests pass. |
| P2 | `docs/` has the privacy, support and changelog pages at fixed URLs. Link check passes. |
| P3 | Settings › About shows the version and working links. AppInfo tests pass. |
| P4 | `-demoData` gives an unlocked, populated iPhone app with direct screen routes. Release build contains no demo code. |
| P5 | The watch shows running and idle demo states and has its icon. |
| P6 | `scripts/screenshots.sh` regenerates all App Store and guide images at the correct sizes. |
| P7 | All 11 guide pages are published, with images and labels matching the code. README updated. |
| P8 | Metadata passes the length check. The checklist covers every owner step. |

Phases 2, 7 and 8 are docs-only; their "vertical" slice is content → site → link check, with no code layers. Phase 7 depends on the Phase 6 images.
