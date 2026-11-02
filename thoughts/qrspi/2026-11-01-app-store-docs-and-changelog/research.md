# Research Findings

Paths are relative to the repo root. Line refs reflect `main` at `cc709b8`.

## Q1: User-facing screens and flows, and actions on each

### Findings
**Launch path**
- `@main TrainMeApp` (`Sources/TrainMeApp.swift:62-96`) → on store ready: `LockGateView { RootView }` (73-74); on failure: `RecoveryView` (98-123) — "TrainMe couldn't open its data store", buttons "Restore last backup" (110), "Start fresh (then import an export file)" (112) + confirm alert "Delete the data store?" (120).
- `LockGateView` (`Sources/Features/Lock/LockGateView.swift:5-40`): "TrainMe is locked" HeroScreen + "Unlock" (37); authenticates on launch (18), locks on background (21-22), re-auths on active (23-26). `AppLock.authenticate` uses `.deviceOwnerAuthentication` (passcode fallback) on device (`Sources/Services/AppLock.swift:30`), biometrics-only on simulator (28), unlocks if no policy is available (36-39).

**RootView tabs** (`Sources/RootView.swift`): Schedule (32), Clients (45), Workouts (55), Exercises (61, `role: .search`), Settings (64, "!" badge when export due, 71). Tab bar minimizes on scroll (73).

**Schedule** (`Sources/Features/Schedule/ScheduleView.swift`)
- Export-reminder banner "Back up your data" with "Export" (→ Settings) and dismiss (14-36).
- Segmented "View" Day/Week (38). Day: graphical DatePicker + session list (46-61). Week: Previous/Next week, "Today" (117-130), per-day sections (132-151).
- "+" → `SessionEditView` sheet (69-71). Rows → `SessionRunView` (98-115). `SessionRow` shows client, time, workouts, repeat icon, status chip (154).
- `SessionEditView` (`Schedule/SessionEditView.swift`): "New Session"/"Edit Session"/"Edit Following Sessions" (156); Client picker (77), Starts (87), Duration stepper 15–240 (91); on create: Workouts multi-select (100), "Repeats weekly" + weekday buttons + "For N weeks" 1–26 (122-140); Notes (144); "Add to iPhone calendar" toggle (150).

**Session run** (`Sources/Features/Session/SessionRunView.swift`)
- Title = client name (129). Sections: Health & limitations (51-66), Time/Status/Repeats (68-76), Session notes + "Save notes" (78-85), one section per workout instance with `SetTableView` (87-112).
- Status buttons while scheduled: "Mark Completed", "Cancelled", "No-show" (114-126); series occurrences get a scope dialog "This session only"/"This and following sessions" (233-245).
- Toolbar: "Text reminder" → `MessageComposeView` (153, 207-218); "More" menu: Edit session / Delete session (158-161).
- Progress bar while scheduled (130); `TimerBar` bottom inset (140-142); logging a set fires haptic + auto rest timer (139, 144-146) and sets watch "up next" (147).
- `SetTableView` (`Session/SetTableView.swift`): columns Set/Prev/metrics (81-90); logged rows deletable (100); draft row: copy previous (112), tap value to edit with stepper strip (127, 183-209), "Log set N" (139); timed sets: "Start N s countdown"/"Stop countdown", finished countdown prefills duration (153-166, 71-76).
- `TimerBar` (`Sources/Features/Timer/TimerBar.swift`): idle "Rest" menu of quick picks (19-24, 57-66); running: label, countdown, progress, "Change", "+N s", "Skip" (26-55).

**Clients** (`Sources/Features/Clients/`)
- `ClientListView`: searchable (47), rows → detail (18-30), "+" → `ClientEditView` (50-58) then alert "Start intake for <name>?" → `IntakeFlowView` (59-81); "Add yourself" empty-state action → self sheet (41, 82, 98-102).
- `ClientEditView`: "About You"/"Edit Client"/"New Client" (28); sections Contact, Training, Profile (DOB, occupation, history, availability), Emergency contact, Physician, Notes (55-112); phone validation.
- `ClientDetailView`: Contact (32), Profile (48), Health & Clearance with badge, stale-screening warning, Latest/New screening (78-92), Waiver (97-100), Assessments (101-119), Upcoming (123) / Recent sessions (132), "View progress" → report (141); "More actions": Edit, Start intake, Archive/Unarchive (162-194).

**Intake** (`Sources/Features/Intake/IntakeFlowView.swift`): steps Choose sections → Profile → Health screening → Waiver → Measurements → Movement → Review (`IntakeFlowViewModel.swift:4-20`); title "<step> (i/n)" (19); Cancel w/ discard prompt (23, 44-49), Next/Done (28), Back (38); Review summary with waiver status and assessment link (90-107).

**Health / Assessments / Waiver**
- `HealthScreeningEditView` (`Features/Health/`): Screening questions (47-54), Clearance (71), Medical history (78), Lifestyle (85), Notes (102).
- `AssessmentEditView` (`Features/Assessments/`): section toggles Measurements / Overhead Squat / Single Leg Squat (18-22); Vitals/Body/Fitness (63); OHS anterior/lateral/posterior + SLS compensation grids with R/L toggles (108; `CompensationGrid.swift:28`). `AssessmentDetailView`: "Changes since <date>", Measurements, Overhead Squat, Single Leg Squat (15-58).
- `ClientWaiverSection` (`Features/Waiver/`): "Send waiver…" → PDF share sheet (12, 44); "Mark signed & returned…" (16, 49-71); History with "Clear signed" swipe (26-31). `WaiverTemplateEditView` (from Settings): TextEditor, Save, "Reset to starter text" (44-60).

**Reports** (`Sources/Features/Reports/`)
- `ClientReportView`: "<name> — Progress" (69); Window picker (21); Consistency, Weekly volume, Sessions, Top exercises → `ExerciseReportView` (56-58); Share menu (72).
- `ExerciseReportView`: Personal best, Top-set weight, Estimated 1RM (Epley), Total reps, History; Share menu (45-48).
- `ShareReportMenu` → "Share PDF" / "Share PNG" `ShareLink`s (`Components/ShareReportMenu.swift:4-17`).

**Workouts / Exercises**
- `WorkoutListView`: tap → builder sheet (14-15), swipe Delete/Duplicate (24-31), "+" (44). `WorkoutBuilderView`: name (26), exercise list with reorder/delete (28-43), "Add exercise" → searchable picker (66, 109-133), per-entry Targets sheet: Sets/Reps/Weight/Duration (144-172).
- `ExerciseListView`: searchable (35), Category filter menu (39), "+" (48), tap to edit (11), "Custom" capsule (16). `ExerciseEditView`: Name, Category, tracked metrics toggles, default unit (61-72).

**Settings** (`Sources/Features/Settings/SettingsView.swift`): Units (55), Client intake → waiver template (66), Timers default rest (76), Backup: Export all data… / Import from file… (merge or replace) / Last export (86-105, 140-184), Permissions rows with "Open Settings" link (108-123, 225-239).

**Watch** (`Watch/`): single screen, no navigation. `TimerScreen` (3-41): running → "Rest"/"Timed set", ring countdown, "+N s", "Skip"; idle → `QuickStartView` (4-33): "<exercise> · N s" up-next button + "Rest N s" quick picks. Haptic at zero (`WatchTimerModel.swift:77`); local notification when suspended (`WatchNotifier.swift`).

## Q2: First-run behavior, empty states, existing in-app help

### Findings
- **Seeding** happens in RootView `.task` every launch, idempotent: `SeedImporter.seedIfEmpty` (`Sources/RootView.swift:104-118`; `Sources/Persistence/SeedImporter.swift:14-41`, returns if any exercise exists, line 15). Failure alert "Couldn't load the exercise library" (`RootView.swift:99-103`). Then requests notification permission (116).
- `Sources/Resources/seed_exercises.json`: 34 exercises — strength 17, bodyweight 8, cardio 5, mobility 3 (e.g. Back Squat, Deadlift, Plank, Treadmill Run, Foam Rolling).
- Waiver starter text is not seeded at launch; loaded on first use of the template (`Sources/Persistence/WaiverRepository.swift:5, 21-28`). `waiver_starter.txt` is a 29-line template with a hidden "not legal advice" comment (line 1) and ALL-CAPS section headings.
- **First-run alert** "Your data lives only on this iPhone" — "There is no cloud backup in this version…" with "Got it" / "Add yourself as a client" (`RootView.swift:7, 76-85`, `@AppStorage("hasSeenBackupNotice")`).
- **Empty states** (`Components/EmptyState.swift:4-21` wraps `ContentUnavailableView`): "No sessions this day" (`ScheduleView.swift:58`), "No exercises" (`ExerciseListView.swift:31`), "No workouts yet" (`WorkoutListView.swift:38`), "No clients yet"/"No matches" + "Add yourself" (`ClientListView.swift:36-44`). Reports: "No completed sessions yet — Progress charts appear after recording sets in completed sessions." (`ClientReportView.swift:14-18`), "Not enough data yet" (114-118, 175-176). Many inline "No …" labels (e.g. `ClientDetailView.swift:125,134`, `SessionEditView.swift:102`).
- **Help text** exists only as Form footers/notes; no `.help`, no About screen, no version/contact/license UI. Examples: Units footer (`SettingsView.swift:63`), Timers (83), Backup "Your data lives only on this iPhone. Exporting to a file is the ONLY backup…" (105), Permissions "Session reminders fire 24 hours and 1 hour before…" (122); screening "not a diagnosis" (`HealthScreeningEditView.swift:68`); waiver "client signs the PDF outside the app" (`ClientWaiverSection.swift:42`); waiver formatting rules (`WaiverTemplateEditView.swift:32`); intake notes (`IntakeFlowView.swift:48, 68`); calendar push note (`SessionEditView.swift:152`).

## Q3: Version, build, name, IDs, targets, devices, icon

### Findings
- **iOS version/build**: literals in `Sources/Info.plist:17-20` — `CFBundleShortVersionString` 1.0, `CFBundleVersion` 1. iOS target in `project.yml:12-27` sets no `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`; uses `INFOPLIST_FILE` with `GENERATE_INFOPLIST_FILE: NO` (21-22).
- **Watch version/build**: `MARKETING_VERSION: "1.0"`, `CURRENT_PROJECT_VERSION: "1"` (`project.yml:42-43`), generated Info.plist (38). The two targets' versions are defined independently.
- **Display name**: `CFBundleDisplayName` TrainMe (`Info.plist:21-22`); watch `INFOPLIST_KEY_CFBundleDisplayName: TrainMe` (`project.yml:39`).
- **Bundle IDs**: `com.madacgrav.trainme` (`project.yml:20`); `com.madacgrav.trainme.watchkitapp` (37); companion key (40); `WKRunsIndependentlyOfCompanionApp: NO` (41). iOS target embeds watch (26-27).
- **Deployment targets**: iOS 26.0, watchOS 26.0 (`project.yml:3-5, 31`).
- **Device family / orientation**: `project.yml` sets no `TARGETED_DEVICE_FAMILY`. The on-disk `TrainMe.xcodeproj` is git-ignored (`.gitignore:11`) and stale (contains no TrainMeWatch target); it shows `TARGETED_DEVICE_FAMILY = "1,2"` for the iOS app. Orientation: portrait only, no `~ipad` key (`Info.plist:23-26`). `UILaunchScreen` empty dict (31-32).
- **Category**: `LSApplicationCategoryType` not set anywhere.
- **Icon**: Icon Composer bundle `Sources/AppIcon.icon/icon.json` (dumbbell + rising line glass layers, light/dark backgrounds, tinted mono line, `supported-platforms` circles watchOS + squares shared, 2-107); `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` on iOS only (`project.yml:23`). Watch target sets no app-icon name and its sources contain no icon. Rendered icon variants exist as PNGs: `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/p5-icon-{default,dark,clear,tinted}.png`.
- **Runtime reads**: only `DataArchive.swift:46` reads `CFBundleShortVersionString` into the export envelope `appVersion`. `CFBundleVersion` never read. No version shown in UI. Store backups key off schema version, not app version (`TrainMeApp.swift:19`, `StoreBackup.swift:7-9`).

## Q4: Permissions, data collection, storage, sharing

### Findings
- **Usage strings** (`Sources/Info.plist`): Calendars full access "TrainMe adds your training sessions to your calendar and removes them when cancelled." (27-28); Face ID "TrainMe locks your client data behind Face ID." (29-30). No contacts/photos/health/location/mic keys.
- **Privacy manifest** `Sources/PrivacyInfo.xcprivacy`: tracking false, no tracking domains, `NSPrivacyCollectedDataTypes` empty, one accessed API: UserDefaults reason `CA92.1` (5-21). iOS target only; watch has none.
- **Entitlements** `Sources/TrainMe.entitlements`: empty dict (4) — no iCloud/CloudKit/app groups/push/HealthKit.
- **Network / SDKs**: no `URLSession`, URLs, analytics, CloudKit; no package dependencies in `project.yml`.
- **Storage**: SwiftData at `Application Support/default.store` (`TrainMeApp.swift:13`; `PersistenceController.swift:8-23`, no `cloudKitDatabase`). UserDefaults keys: `hasSeenBackupNotice`, `lastExportAt`, `wantsSelfClient` (`RootView.swift:7-9`), default weight unit, default rest, `lastRunSchemaVersion`. Schema backups in `Application Support/Backups/pre-schema-<v>/` (`StoreBackup.swift:18-72`).
- **Personal data in models**: Client name, phone, goal, injuries, notes, DOB, emergency contact, physician, occupation, training history, availability (`Sources/Models/Client.swift:5-27`); HealthScreening 7 yes/no questions + conditions, surgeries, medications, family heart history, symptoms, sleep, stress, tobacco, alcohol, activity, clearance date (`HealthScreening.swift:17-56`); Assessment vitals/body measurements/fitness tests + movement compensations (`Assessment.swift:102-149`); waiver records (dates + template snapshot, no signature image) (`Waiver.swift`); sessions, sets.
- **Data leaving the app (all user-initiated)**:
  - Calendar event "Training: <clientName>" + session notes to device calendar (`CalendarService.swift:101-114`); one-way push.
  - Local notifications "<clientName> at <time>" 24 h/1 h before (`NotificationService.swift:35-44, 73`); timer-end notifications (`TimerNotificationService.swift:13-51`).
  - SMS compose prefilled "Hi <firstName>, reminder: our session…" — user taps Send (`MessagingService.swift:8-38`).
  - Report PDF/PNG via ShareLink, files in `tmp/Reports` with complete protection (`ReportExporter.swift:23-57`).
  - Waiver PDF via share sheet, `tmp/Waivers` (`WaiverPDFRenderer.swift:12-60`).
  - Full JSON export via file exporter (`DataArchive.swift:36-64`; `SettingsView.swift:140-157`); import merge/replace with pre-import snapshot (`SafeImporter.swift:18, 60`).
  - WatchConnectivity sends only timer state + up-next exercise name/seconds, quick picks, default rest — no client data (`Shared/Sync/TimerSnapshot.swift:4-10`, `UpNext.swift:4-9`, `WatchSyncService.swift:50-60`; commands `TimerCommand.swift:5-9`).

## Q5: Rendering with representative data outside normal use

### Findings
- **`#Preview`s** in ~23 files; nearly all use `PreviewFixtures.repositories()`. Exceptions: `TimerBar.swift:69` (`TimerStore.preview`, `TimerStore.swift:63`), `Watch/TimerScreen.swift:43, 52` (inline `TimerSnapshot`). Notable: `ScheduleView.swift:185, 197` ("Schedule — Week" with `seedingWeek: true`), `SessionRunView.swift:325`, `ClientReportView.swift:192`, `ClientEditView.swift:119` ("About you"), `AssessmentEditView.swift:153, 161`.
- **`Sources/Support/PreviewFixtures.swift`**: client "Sam Rivera" (13), screening (23), two assessments a month apart (31), "Bench Press"/"Goblet Squat" (49-53), workout "Upper A" (58), today's 9:00 session (63), series session (81), four week sessions (94), two logged sets (128). `container(seedingWeek:)` builds an in-memory store (176-190); `repositories()` (156). Single-client dataset; not reachable from the running app.
- **Test fixtures**: `Tests/Fixtures/export-v1.json`, `export-v2.json` (frozen archive exports, loaded at `ArchiveRoundTripTests.swift:149, 216`). These are importable JSON in the app's own archive format.
- **No launch arguments, env checks, `#if DEBUG`, demo mode, or UI-test target** anywhere (grep of `ProcessInfo`, `launchArguments`, `#if DEBUG`, `uitest`, `demo`). Only runtime seeding is the exercise library.
- **Schemes**: `TrainMe` (tests: TrainMeTests) and `TrainMeWatch` (build only) (`project.yml:53-63`); no `.xctestplan`.
- **CI** `.github/workflows/ci.yml`: macos-26, Xcode 26, `xcodegen generate`, test on `iPhone 17` simulator, watch generic build; no screenshot/xcresult upload.
- **Existing screenshots**: 43 PNGs in `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/`, named `p<N>-<screen>-{light,dark,ax3}.png` (schedule, clients, exercises, workouts, settings, session, report, builder, client-detail, lock, about-you) + `p5-icon-*`. Captured manually on a booted simulator via `xcrun simctl ui booted appearance light|dark`, `content_size accessibility-extra-large`, `xcrun simctl io booted screenshot` (that dir's `plan.md:17-25`, `structure.md:10-13`). Notes do not record the device model or how data was populated. No watch screenshots exist. Pixel dimensions not checked.

## Q6: Chronological history of user-visible changes

### Findings
No git tags; version has been 1.0 (1) since `b3a6d84`. Issue numbers (#3–#30, #38) are GitHub issues, not PRs.

| Date | PR | Branch | User-visible changes | Schema |
|---|---|---|---|---|
| 2026-07-08 | — | main | `0a973d1` initial commit | — |
| 2026-07-09 | #1 `293f8c1` | 2026-07-08-trainme-ios-app | Initial app: clients, exercise library + seed, workout builder, scheduling w/ weekly recurrence + calendar push, run/record sessions, history & progression reports, reminders (notifications + text), report sharing, JSON export/import, Face ID lock, store recovery | unversioned models |
| 2026-07-09 | direct | main | `ac5a23f` app-lock dead end on simulator fixed | — |
| 2026-10-26 | #2 `371bb37` | fix/review-findings | Backup restore fix, correct series length, no phantom calendar event, set deletion with session, Face ID sheet once, cancelled sessions stop alerting, temp-file protection | — |
| 2026-10-26 | #31 `73835e4` | feature/icon-and-p0-gaps | App icon + amber accent, portrait-only; destructive-action confirmations, save-failure banners; injuries + notes on run screen; per-exercise units; edit/delete session; export-staleness banner | — |
| 2026-10-26 | #32 `6344ac6` | 2026-10-26-tech-debt | Safe replace-import with rollback; notification permission gate + Permissions rows; calendar fallback; run-screen error state, seed-failure alert; privacy manifest | SchemaV1 frozen (`a49adc2`) + schema backups |
| 2026-10-26 | #34 `1d51824` | 2026-10-26-p1-reporting | Total-reps chart, exercise detail, consistency window, weekly volume, top exercises, PNG export + overview page | — |
| 2026-10-26/27 | #36 `0c7a624` | 2026-10-26-ui-refresh-and-icon | UI refresh/theme, inline set table, "About you" self client, icon variants (dark/tinted/clear), accessibility (AX3) | SchemaV2: `Client.isSelf` (`9842aa8`) |
| 2026-11-01 | #39 `8c0fd64` | GH-7-series-edit-cancel-calendar | Repeating sessions: edit/cancel/delete "this only" or "this and following", calendar kept in sync | — |
| 2026-11-01 | #40 `d47fea0` | GH-8-schedule-week-view | Schedule week view, week navigation, remembered mode | — |
| 2026-11-01 | #41 `2b593fd` | 2026-11-01-nasm-movement-assessment | Client intake: extended profile, health screening + clearance, NASM OHS/SLS assessments + measurements, liability waiver (PDF send, mark signed, editable template), guided intake flow | SchemaV3: Client profile fields; new HealthScreening, Assessment, WaiverTemplate, WaiverRecord (`d9376c3`); archive format v2 |
| 2026-11-01/02 | #42 `cc709b8` | GH-38-quick-timers-watch | Rest timer, timers survive background/lock/relaunch, timed-set countdown, **Apple Watch app** (mirror, start/control, wrist cue at zero) | — |

Docs-only merges: #33, #35, #37. Migration plan V1→V2→V3 lightweight (`Sources/Persistence/SchemaV1.swift:218-220`). Watch `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` first added in `42fa426` (#42).

## Q7: Existing product documentation

### Findings
- **README.md** (67 lines): one-line pitch "A local-only iOS app for an independent personal trainer…" (5-8); build via XcodeGen (10-39); requirements Xcode 26+, iOS 26 (41-44); permissions notes (46-55); layout (57-67). No audience detail beyond L5, no support/contact, no license mention, no watch/timer mention.
- **PRD.md** (214 lines, "Version 0.1 (draft)", 2026-07-08, Owner Adam, L3-6): local-only single-trainer iOS app (10-14); non-goals: billing, client app, multi-trainer, cloud, nutrition/photos/payments, Android (26); "personal now, sellable later" (33); target user: independent trainer, non-technical, spotty connectivity, one-handed entry; clients are records not users (37-41); data model incl. intake "shipped 2026-11" (45-98); P0–P2 features (102-137); export risk "should be stated plainly in onboarding" (181); security: Face ID, Data Protection, no analytics; commercialization would require a privacy policy and client-consent capture (185-187). No watch/timers, no support contact, no licensing.
- **BACKLOG.md** (119 lines): open P1 (inline create exercise #9, archived clients browse #10) and P2 items (CSV export, more recurrence, RPE, deletes, snapshot tests, intake follow-ups, quick timers row 34 still listed open) (32-55); deferred (57-62); done tables per PR (64-119).
- **LICENSE**: GNU GPL v3 (`LICENSE:1-2`), stock FSF text, no project copyright line; not referenced by README/PRD.

## Cross-Cutting Observations
- The app is entirely on-device: no network, accounts, analytics, or SDKs; every outbound data path is a user-initiated system sheet (calendar, share, SMS, file export) (Q4).
- Health-adjacent personal data about third parties (clients) is stored — screening answers, medications, vitals — though the app has no HealthKit (Q4).
- `project.yml` is the source of truth; `TrainMe.xcodeproj` is generated and git-ignored, and the local copy is stale (Q3).
- Version metadata lives in two different mechanisms (plist literal for iOS, build settings for watch) and has never changed from 1.0 (1); history exists only as PR merges and `thoughts/qrspi/*` directories (Q3, Q6).
- Representative data exists only in `PreviewFixtures` (one client) and frozen export fixtures; the running app has no sample-data path (Q5).
- Existing explanatory copy is concentrated in Form footers and alerts; there is no About/Help surface (Q2).
- PRD and README predate the watch app and timers (Q7).

## Open Areas
- Effective `TARGETED_DEVICE_FAMILY` after a fresh `xcodegen generate` was not verified (stale project shows "1,2"; Info.plist has no iPad orientation key).
- Pixel dimensions and device model of existing screenshots were not determined.
- Contents of `Tests/Fixtures/export-v2.json` (how many clients/sessions) were not enumerated.
- `Watch/WatchNotifier.swift` and `Shared/Sync/SyncCodec.swift` were not read in full.
- Whether the watch app builds its icon from `Sources/AppIcon.icon` (watch target sources don't include it) was not verified.
