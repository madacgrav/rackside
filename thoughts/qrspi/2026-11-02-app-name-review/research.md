# Research Findings

Scope: `Sources/`, `Watch/`, `Shared/`, `Tests/`, `project.yml`, `.github/`, `docs/`, `scripts/`, `PRD.md`, `README.md`, `CHANGELOG.md`. `build/` and `thoughts/` excluded. Q7 is web research; everything there is from search results and fetched pages, not primary registries.

## Q1: Where does "TrainMe" / "trainme" appear in the app and watch targets, user-visible vs internal?

### Findings

No `.strings` / `.xcstrings` files exist. `Shared/`, `PrivacyInfo.xcprivacy` and the entitlements file contents have no matches.

**User-visible (14 occurrences)**

| # | Location | Text / role |
|---|----------|-------------|
| 1 | `Sources/Info.plist:21-22` | `CFBundleDisplayName` = "TrainMe" (iPhone home-screen name) |
| 2 | `project.yml:47` | `INFOPLIST_KEY_CFBundleDisplayName: TrainMe` (watch home-screen name) |
| 3 | `Sources/Info.plist:28` | Calendar usage string: "TrainMe adds your training sessions to your calendar…" |
| 4 | `Sources/Info.plist:30` | Face ID usage string: "TrainMe locks your client data behind Face ID." |
| 5 | `Sources/Services/AppLock.swift:42` | `localizedReason: "Unlock TrainMe"` |
| 6 | `Sources/Features/Lock/LockGateView.swift:48` | Lock screen title "TrainMe is locked" |
| 7 | `Sources/TrainMeApp.swift:118` | Alert title "TrainMe couldn't open its data store" |
| 8 | `Sources/Features/Settings/SettingsView.swift:216` | "This file was exported by a newer version of TrainMe. Update the app first." |
| 9 | `Sources/Features/Settings/SettingsView.swift:220` | "Import failed: the file isn't a valid TrainMe export." |
| 10 | `Sources/Services/ReportExporter.swift:77` | `Text("TrainMe Progress Report")` (PDF/PNG header) |
| 11 | `Sources/Services/ReportExporter.swift:115` | same, second render path |
| 12 | `Sources/Services/TimerNotificationService.swift:16` | Notification body "Log the set in TrainMe." |
| 13 | `Watch/WatchNotifier.swift:24` | Notification body "Log the set in TrainMe." |
| 14 | `Sources/Services/Archive/DataArchive.swift:36` | Export file name `"TrainMe Export \(day).json"` |

No accessibility labels contain the name.

**Internal (≈72 occurrences)**

- Swift types: `TrainMeApp` (`Sources/TrainMeApp.swift:74`), `TrainMeWatchApp` (`Watch/TrainMeWatchApp.swift:4`), `TrainMeMigrationPlan` (`Sources/Persistence/SchemaV1.swift:216`, used at `PersistenceController.swift:20`, `Tests/SchemaTests.swift:12-13`, `Tests/MigrationTests.swift:19`).
- Logger subsystem `"com.madacgrav.trainme"` (`Sources/Support/Log.swift:5`), shared by all six loggers (lines 6-11).
- URLs: `https://madacgrav.github.io/trainme/` (`Sources/Support/AppInfo.swift:15`), `https://github.com/madacgrav/trainme/blob/main/LICENSE` (`AppInfo.swift:20`), `Tests/AppInfoTests.swift:22`. Opened via `AppLinks`, not shown as text.
- `project.yml`: project name (1), targets `TrainMe` / `TrainMeWatch` / `TrainMeTests` (14, 31, 51), entitlements path (27), target deps (30, 56), bundle IDs (22, 45, 48), schemes (61-70).
- CI: `-scheme TrainMe` and `-scheme TrainMeWatch` (`.github/workflows/ci.yml:24, 30`).
- Tests: 43 `@testable import TrainMe` lines (module name, one per test file); `TrainMe.Unit` (`Tests/ReportingTests.swift:61`).
- Filename only: `Sources/TrainMe.entitlements` (content is an empty dict).

**Where the home-screen name comes from**

- iPhone target sets no `PRODUCT_NAME` or `INFOPLIST_KEY_CFBundleDisplayName`; it uses a hand-written plist (`GENERATE_INFOPLIST_FILE: NO`, `INFOPLIST_FILE: Sources/Info.plist`, `project.yml:23-24`). `PRODUCT_NAME` defaults to the target name. `CFBundleName` = `$(PRODUCT_NAME)` (`Sources/Info.plist:13-14`); the displayed name is the literal `CFBundleDisplayName` (`Info.plist:21-22`).
- Watch target: generated plist (`project.yml:46`), display name from `project.yml:47`.

## Q2: Which runtime behaviours depend on the bundle identifiers?

### Findings

Declared IDs: iOS `com.madacgrav.trainme` (`project.yml:22`; `Sources/Info.plist:9-10` sets `CFBundleIdentifier` to `$(PRODUCT_BUNDLE_IDENTIFIER)`); watch `com.madacgrav.trainme.watchkitapp` (`project.yml:45`), `WKCompanionAppBundleIdentifier: com.madacgrav.trainme` (`project.yml:48`), `WKRunsIndependentlyOfCompanionApp: NO` (`project.yml:49`). The iOS target depends on and embeds the watch target (`project.yml:29-30`).

**Only hard-coded bundle-ID string in Swift:** the logger subsystem (`Sources/Support/Log.swift:5`). No code reads `Bundle.main.bundleIdentifier`; `Bundle.main` is used only for version lookups (`DataArchive.swift:46`, `AppInfo.swift:6`) and the `waiver_starter.txt` resource (`DemoData.swift:155`).

**SwiftData store**
- `PersistenceController.makeContainer` (`Sources/Persistence/PersistenceController.swift:8-23`) creates `.applicationSupportDirectory` (line 12) and a `ModelConfiguration(isStoredInMemoryOnly:)` with no name, URL, group container or CloudKit database (line 17). The store is the SwiftData default inside the app sandbox.
- `AppBootstrap.storeURL = URL.applicationSupportDirectory.appending(path: "default.store")` (`Sources/TrainMeApp.swift:13`) is used for backup, restore and reset (lines 30, 40, 51-59).
- `StoreBackup` writes `<store dir>/Backups/pre-schema-<version>/` (`Sources/Persistence/StoreBackup.swift:34, 70-72`), copying store + `-wal` + `-shm` (line 11); tracks `lastRunSchemaVersion` / legacy `lastRunAppVersion` in `UserDefaults.standard` (lines 7, 9, 21).
- `SafeImporter` snapshot `pre-import.json` also lives in Application Support (`Sources/Services/Archive/SafeImporter.swift:18`).

**Watch pairing:** only `WKCompanionAppBundleIdentifier` (`project.yml:48`) expresses the relationship. WatchConnectivity uses `WCSession.default` on both sides (`Sources/Services/WatchSyncService.swift:34-35`, `Watch/PhoneLink.swift:11-13`); no bundle ID in code. The watch has no SwiftData store; data moves via application context, messages and userInfo.

**Entitlements / groups / keychain:** `Sources/TrainMe.entitlements` is an empty `<dict/>` (lines 4-5). No watch entitlements file. No `group.` string anywhere. No keychain usage.

**UserDefaults:** production uses `.standard` only (`StoreBackup.swift:21`, `TimerStore.swift:40`, `ScheduleViewModel.swift:42`, `ReminderCoordinator.swift:37`, plus `@AppStorage` keys `hasSeenBackupNotice`, `lastExportAt`, `wantsSelfClient`, `defaultWeightUnit`, `TimerSettings.defaultRestKey`). Named suites exist only in previews/tests (`TimerStore.swift:64`, `ScheduleView.swift:205`).

**Notifications:** no categories. Request IDs `sess-<uuid>-24h` / `-1h` (`NotificationService.swift:32, 41`), `timer-<uuid>` (`TimerNotificationService.swift:44`, `Watch/WatchNotifier.swift:8, 27`). Not bundle-ID prefixed.

**Background tasks / URL schemes:** none. No `BGTaskScheduler`, no `CFBundleURLTypes`; only `UIApplication.openSettingsURLString` (`SettingsView.swift:244`).

**General Apple platform behaviour (not from the repo):** the sandbox container (Documents, Library/Application Support, Caches, tmp, standard UserDefaults) is keyed to the bundle identifier. An app installed under a different bundle ID is a separate app with a new empty container; the old app and its data remain until the old app is deleted. Notification, Calendar and Face ID grants and the watch pairing are also per bundle ID. Installing the same ID over an existing install preserves data.

## Q3: How do the export archive and import path identify a valid file?

### Findings

- Envelope (`CurrentArchive` = `ArchiveV2.Envelope`, `Sources/Services/Archive/ArchiveV2.swift:11-24, 44`): `schemaVersion` (default 2), `exportedAt`, `appVersion` (from `CFBundleShortVersionString`, `DataArchive.swift:46`), then entity arrays (`clients`, `exercises`, `workouts`, `sessions`, `setRecords`, `healthScreenings`, `assessments`, `waiverTemplate?`, `waivers`). Encoded ISO8601, pretty-printed, sorted keys (`DataArchive.swift:57-60`). **No product name, bundle ID, magic value or type tag in the body.**
- File name: `"TrainMe Export <yyyy-MM-dd>.json"` (`DataArchive.swift:36`), written to `tmp/Exports/` (lines 63-64) with complete file protection (line 39). The name is a default only; import never inspects it.
- UTType: export and import both use generic `.json` (`SettingsView.swift:151-155, 169`). No custom UTType, no `UTExportedTypeDeclarations` or `CFBundleDocumentTypes` in `Info.plist`.
- Validation (`importData`, `DataArchive.swift:86-106`): (1) decode `VersionProbe { schemaVersion: Int }` (`ArchiveV1.swift:25-27`) else `ArchiveError.unreadable`; (2) `schemaVersion > 2` → `ArchiveError.newerThanApp`; (3) `...1` → decode `ArchiveV1.Envelope` then `ArchiveV2.migrate` (`ArchiveV2.swift:26-40`, fills new arrays empty, `waiverTemplate: nil`); `default` → decode `ArchiveV2.Envelope`; (4) decode failure → `ArchiveError.decodeFailed`.
- The product name enters only the error strings shown in Settings (`SettingsView.swift:216, 220`); `unreadable` (line 218) does not name the app.
- Golden fixtures `Tests/Fixtures/export-v1.json` (`schemaVersion: 1`, `appVersion: "1.0"`) and `export-v2.json` (`schemaVersion: 2`, `appVersion: "1.1"`) contain no product name or bundle ID; loaded by `Tests/ArchiveRoundTripTests.swift:148-150, 215-217`.
- Replace import: `SafeImporter.importReplacing` snapshots to `pre-import.json`, imports, restores on failure (`SafeImporter.swift:25-42`); `deleteAll()` precedes `upsertAll` (`DataArchive.swift:109-113`).

## Q4: How is the name used in docs, App Store kit, changelog and scripts?

### Findings

**Docs site config** (`docs/_config.yml`): `title: TrainMe` (1), `baseurl: /trainme` (4), `url: https://madacgrav.github.io` (5) → Pages URL `https://madacgrav.github.io/trainme/`. `exclude: app-store` (6-7) keeps the App Store kit unpublished. The `description` (2) has no name.

**Matching lines per file (case-insensitive)**

| File | Lines |
|------|-------|
| `CHANGELOG.md` / `docs/changelog.md` (generated copy) | 23 / 23 |
| `docs/app-store/metadata.md` | 14 |
| `docs/privacy.md` | 13 |
| `docs/support.md` | 12 |
| `README.md` | 9 |
| `docs/guide/backup-and-restore.md` | 7 |
| `docs/app-store/checklist.md` | 6 |
| `docs/guide/troubleshooting.md` | 6 |
| `docs/guide/getting-started.md` | 5 |
| `docs/index.md`, `docs/guide/index.md` | 4 each |
| `docs/guide/scheduling.md`, `apple-watch.md` | 3 each |
| `PRD.md`, `docs/guide/clients-and-intake.md`, `health-assessments-waivers.md`, `settings.md` | 2 each |
| `docs/app-store/whats-new/1.0.0.md`, `docs/guide/reports.md`, `running-a-session.md` | 1 each |
| `docs/guide/workouts-and-exercises.md` | 0 |

- `docs/app-store/TrainMe Review Sample.json`: name only in the filename; body has no matches.
- Screenshot and guide image filenames do not contain the name.

**`docs/app-store/metadata.md`**: Name field `TrainMe` (7-9); Subtitle "Personal trainer client log" (13-15); Keywords (68-70) do **not** include the name; Support/Marketing/Privacy URLs under `madacgrav.github.io/trainme/` (78-80); Copyright "2026 Adam (madacgrav)" (85, placeholder note 88); Description opens "TrainMe is the client and session log…" (26) and closes at 63; Review notes name the app and the sample file (114-127); Pricing USD 0.99, all territories, no IAP (95-98).

**`docs/app-store/checklist.md`**: title (1), Pages URLs (14), name / bundle ID `com.madacgrav.trainme` / SKU `trainme-ios` (20), `TrainMe.xcodeproj` (28), sample file attachment (37), "TrainMe is GPL v3" (7).

**Lowercase `trainme` as path/URL**: `CHANGELOG.md:11` site link, many `github.com/madacgrav/trainme/pull/N` links, compare links (`CHANGELOG.md:96-102`, `docs/changelog.md:101-107`); `README.md:3` CI badge, `:11-12` guide/privacy/support URLs, `:30, 33, 39` scheme/project names; `docs/support.md:11` issues link. `docs/guide/*` uses relative links only; the name there is prose or UI text.

**Git remote**: `origin` = `https://github.com/madacgrav/trainme.git` (`.git/config:8-10`).

**Scripts (`scripts/`, 5 files)**

| Script | Hard-codes name / path? | Limits enforced |
|--------|------------------------|-----------------|
| `check-metadata-lengths.sh` | No | `LIMITS` (line 8): Name 30, Subtitle 30, Promotional Text 170, Description 4000, Keywords 100, Review Notes 4000; each `whats-new/*.md` text block ≤ 4000 (line 26). Copyright, URLs, category unchecked. |
| `check-docs-links.sh` | Yes: `/trainme/*` → `docs/` (line 16) | None. Scans `docs/**/*.md` (not `app-store/`) and `README.md`. |
| `check-guide-labels.sh` | No | Backticked labels in `docs/guide/*.md` must appear as `"label` literals in `Sources/` or `Watch/*.swift`; labels < 3 chars skipped. |
| `screenshots.sh` | Yes: scheme `TrainMe` (42), `TrainMe.app` (44), `Watch/TrainMeWatch.app` (45), bundle IDs (96, 110) | Image sizes: iPhone 1320×2868 or 1290×2796 (120); watch 422×514 / 410×502 / 416×496 / 396×484 / 368×448 (125); phone PNG ≥ `MIN_PHONE_BYTES` 150000. |
| `sync-changelog.sh` | No | Regenerates `docs/changelog.md` from `CHANGELOG.md` with `title: Changelog`, `permalink: /changelog/`. |

## Q5: Do the icon, assets or screenshots contain the name as text or wordmark?

### Findings

- `Sources/AppIcon.icon/icon.json` references layers `dumbbell.svg`, `line.svg` / `line-mono.svg`, `background.svg` / `background-dark.svg`. No `<text`, `<tspan` or `font` in any icon file. The watch target reuses the icon (`project.yml:38-39`).
- `docs/images/icon.png` (viewed): teal-to-blue rounded square, white dumbbell, orange rising line, no text.
- `Sources/Assets.xcassets` contains colorsets only (AccentColor, BrandPrimary, BrandSecondary, Danger, PersonalBest, Success, Surface, SurfaceRaised, Warning). `Watch/` has no asset catalog.
- Screenshots viewed (`docs/app-store/screenshots/01-schedule-week`, `02-session-timer`, `03-client-detail`, `04-progress-report`, `w1-timer-running`): no "TrainMe" visible. Text seen is status bar, nav titles ("Schedule", "Jordan Lee", "Jordan Lee — Progress"), demo names, tab bar (Schedule, Clients, Workouts, Settings, Exercises), watch "Rest / 1:18 / +15 s / Skip". Not viewed: `05-assessment`, `06-workout-builder`, `w2-quick-start`.
- Note from Q1: the rendered progress report PDF/PNG does carry "TrainMe Progress Report" as a text header (`ReportExporter.swift:77, 115`); screenshot `04-progress-report` shows the in-app screen, not the export.

## Q6: What do PRD.md and README.md say about audience, features, platforms, price, positioning?

### Findings

**PRD.md** (v0.1 draft, 2026-07-08, owner Adam; lines 3-6)
- Audience: "an independent personal trainer running their own book of business, comfortable with a phone but not technical" (39); trains in gyms/homes "often with spotty connectivity"; records sets quickly, "sometimes one-handed". Clients are "records inside the app, not users" (41); no client login (26); "single trainer" (12).
- Core loop (14): build a workout → schedule a session → run and record → see the client improve over weeks. §5 (102-137) features: client management, exercise library, workout builder, scheduling/calendar, run and record, history, trainer reminders, progress reporting, PDF/image share (P1), export/import, Face ID lock. Client intake "shipped 2026-11" (82-92). "Billing remains deferred" (94).
- Platforms: "iOS only, stores all data locally on the device" (12); "Android is deferred" (26); Swift/SwiftUI/SwiftData, "No backend." (193). PRD does not mention Apple Watch.
- Price: none stated; "in-app payments are out of scope" (26).
- Positioning: "Personal now, sellable later" (33); architecture kept clean for later cloud sync and multi-trainer accounts (12, 191-197); v2 commercial additions listed at 197.

**README.md**
- "a client and session log for independent personal trainers, on iPhone and Apple Watch." (5-6); "Everything stays on the iPhone — no account, no cloud, no tracking." (9).
- Features (6-9): clients' goals, injuries, health screening, assessments, waivers; reusable workouts; schedule and record sessions "set by set with a rest timer on your phone or wrist"; progress over time.
- Platforms: iPhone + Apple Watch (5); Xcode 26+, iOS 26 deployment target (52-53); `Watch/` is a "rest timer mirror and quick start" (76).
- Price: none. "License: GPL v3" (14).
- The USD 0.99 price appears only in `docs/app-store/metadata.md:97-98` and `checklist.md:21`.

## Q7: Who else uses "TrainMe" or close variants?

### Findings

Source: web search and fetched pages only. No direct queries of USPTO TSDR, EUIPO, UK IPO, WIPO or INPI; trademark data below comes from third-party mirrors. Not checked: Google Play search, WHOIS for trainme.com / .app / .io, US-storefront availability of the French apps.

**Apps and products**

| Name | Owner | What | Category | Market | Active? | Source |
|------|-------|------|----------|--------|---------|--------|
| TrainMe: Home & Gym Workout (iOS 6467795772) | Appstack Technologies | AI quiz-based home/gym workouts, "Your personal trainer in your pocket"; free + IAP (~$5.99/mo, $19.99/yr) | Health & Fitness | iOS, apparently global, USD prices | Probably; v2.0.4 "June 4" (year not shown; AppGoblin says 2026, AppAdvice shows v1.9.0 July 2025) | apps.apple.com/app/id6467795772 |
| TrainMe - Votre coach sportif (iOS 1165978033) | TrainMe (French company) | Marketplace to book certified sports coaches; 15 disciplines, 1,000+ coaches; CESU vouchers, 50% tax credit | Health & Fitness, personal training | France | Active; v2.27.03 "1 oct." | apps.apple.com/fr/app/id1165978033 |
| TrainMe Mon Programme (iOS 1542215145) | same brand | Adaptive training programme with Apple Health read; free + IAP | Sports | Multi-country, French-language | Active; v9.52 "30 Jul" | apps.apple.com/ng/app/id1542215145 |
| TrainMe (company, trainme.co) | French startup founded 2015 (Gatien Letartre, Anatole Saby); Decathlon subsidiary/partner per press release and Pluxee | Coach marketplace, 1,400+ coaches, B2C and B2B | Personal training / coaching | France | Appears active; press kit at personal.trainme.co; 2020 turnover ≈ €0.888M | decathlon.media press release; pluxee.fr/enseignes-cadeaux/trainme; maddyness.com 2017-01-03; businesscoot.com |
| TRAIN ME (iOS 6741906566) | FITBEIS | Little detail | Health & Fitness | Seen on DO storefront | Unknown | apps.apple.com/do/app/id6741906566 |
| Train Me (agency case study) | BrightMinded | "Cognitive mobile app for fitness trainers" | Fitness | Unknown | Unknown | brightminded.com/our-work/train-me/ |
| trainme.carrd.co | Unknown | Youth sports training page referencing "the TrainMe app" | Youth sports | Unknown | Unknown | trainme.carrd.co |
| Directory entries (softwarereview.com, prospeo, etc.) | Probably the French company | Listings only | — | — | — | softwarereview.com/s/trainme |

**Trademarks (USPTO, via mirrors)**

| Mark | Owner | Class / goods | Status | Source |
|------|-------|---------------|--------|--------|
| TRAINME, Serial 50009218 | Train-Me LLC, Dover DE | Class 9: downloadable app for scheduling/booking sports training sessions, connecting students with coaches, payments, messaging, profiles | Pending; new application dated 2026-07-23; snippet said "LIVE"; page returned 403 | trademarkelite.com/…/50009218/TRAINME |
| TT TRAINME, Serials 97354478 / 97356579 | Train Me Tech Ltd, London | Not verified | Dead; abandoned 2023 (no response to office action) | markinton.com |
| INSTATRAINME, Serial 98929281 | InstaTrainMe Technologies, Inc. | Not verified | Reported registered 2025-11-11 | trademarkdir.com |
| TRAIN ME TODAY, Serial 98454691 | Not verified | HR services | Pending, filed March 2024 | trademarks.justia.com |

**Domains**: trainme.co is the French coaching platform (evidence: personal.trainme.co press kit, hello@trainme.co). trainme.com / .app / .io not checked; no products on them surfaced in search.

**Near variants seen**: TrainWithMe (iOS 1146555947, personal-training marketplace), "Trainn".

## Cross-Cutting Observations

- The name is a literal string in 14 user-facing places and is not centralised; there is no `AppInfo.name` or similar constant, and no localisation table.
- The bundle ID is referenced as a literal in exactly one Swift file (`Log.swift:5`) and three `project.yml` lines; everything else (store path, UserDefaults, notifications, watch pairing in code) is implicit via the sandbox or `WCSession.default`.
- The on-disk store and the per-app UserDefaults have no name coupling; coupling to identity is entirely through the sandbox container, i.e. through the bundle ID.
- The export archive is name-agnostic in body, UTType and validation; only the default file name and two Settings error strings carry the name.
- The icon and in-app screenshots carry no wordmark; the only rendered artefact with the name is the exported progress report header.
- Outside the repo the name is tied to the GitHub repo path (`madacgrav/trainme`), the Pages `baseurl`, three `AppInfo` URLs, `check-docs-links.sh:16`, and every CHANGELOG link.
- Externally, the name is in use by at least two active fitness/personal-training products (French TrainMe coach marketplace; Appstack "TrainMe: Home & Gym Workout" in the US-priced App Store) and a pending US Class 9 application for TRAINME filed 2026-07-23.

## Open Areas

- Trademark status not confirmed against primary registries (USPTO TSDR, EUIPO, UK IPO, WIPO, INPI). The French TrainMe likely holds an INPI or EU mark; not verified.
- Whether the pending TRAINME application (Train-Me LLC) relates to any listed app is unknown.
- Google Play presence for "TrainMe" / "Train Me" not checked.
- WHOIS for trainme.com, trainme.app, trainme.io not checked.
- Three screenshots (`05-assessment`, `06-workout-builder`, `w2-quick-start`) were not visually inspected for the name.
- `TrainMe Review Sample.json` content was grepped but not otherwise examined for demo text that mentions the app.
