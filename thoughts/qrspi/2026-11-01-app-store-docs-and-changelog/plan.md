# Implementation Plan

## Overview
Make TrainMe ready to submit to the App Store as a paid ($0.99) iPhone + Apple Watch app at version 1.0.0. That means: one version source, a public docs site (guide, privacy, support, changelog), an About section in Settings, debug-only demo data with a reproducible screenshot script, and a complete submission kit.

**Conventions used throughout**
- `project.yml` is the source of truth. After changing it, run `xcodegen generate`. The `.xcodeproj` is git-ignored (`.gitignore:11`).
- **Build/test command** (later steps call it TEST): `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test`. It must pass after every phase. If `iPhone 17` is missing locally, use `iPhone 18 Pro Max`, which is available.
- **Watch build** (WATCH): `xcodebuild -scheme TrainMeWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) with `@testable import TrainMe`, matching `Tests/TimerMathTests.swift:1-3`.
- Simulators on this machine: `iPhone 18 Pro Max` and `Apple Watch Ultra 4 (49mm)`.
- Docs base URL: `https://madacgrav.github.io/trainme/`.
- Copy tone: plain and second person. Quote button and screen labels exactly as they appear in the code.

---

## Phase 1: Version source and changelog

### Changes

#### 1. Project settings
**File**: `project.yml`
**Action**: modify
- Under top-level `settings.base` (next to `SWIFT_VERSION`), add:
  ```yaml
      MARKETING_VERSION: "1.0.0"
      CURRENT_PROJECT_VERSION: "1"
  ```
- In `targets.TrainMeWatch.settings.base`, delete the `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` lines (currently `project.yml:42-43`).
- In `targets.TrainMe.settings.base`, add `TARGETED_DEVICE_FAMILY: "1"`.

#### 2. Info.plist
**File**: `Sources/Info.plist`
**Action**: modify
```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
...
<key>LSApplicationCategoryType</key>
<string>public.app-category.healthcare-fitness</string>
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
For the watch, add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` to the TrainMeWatch settings.

#### 3. Version test
**File**: `Tests/AppVersionTests.swift`
**Action**: create
```swift
import Foundation
import Testing
@testable import TrainMe

/// The host app's plist must resolve the version build settings, not keep literals.
@Test func bundleVersionIsSemanticAndResolved() {
    let info = Bundle(for: BundleAnchor.self).infoDictionary ?? Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? ""
    #expect(short.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
    #expect(!(info["CFBundleVersion"] as? String ?? "$").contains("$"))
}
private final class BundleAnchor {}
```
The test bundle is hosted, so `Bundle.main` is the app. If `Bundle(for:)` returns the test bundle, which has no `CFBundleShortVersionString` in semver form, use only `Bundle.main.infoDictionary`.

#### 4. Changelog
**File**: `CHANGELOG.md`
**Action**: create, in Keep a Changelog 1.1.0 format. Header text: "All notable changes… adheres to Semantic Versioning. Versions before 1.0.0 were development builds and were not released on the App Store."

Write the user-facing content from research Q6. Use no commit hashes; link PRs as `([#N](https://github.com/madacgrav/trainme/pull/N))`.

- **[Unreleased] — 1.0.0**
  - Added: Settings › About, user guide and support site, privacy policy.
  - Changed: iPhone only.
  - (Phases 3–8 append their own lines here.)
- **0.6.0 — 2026-11-02** (#42)
  - Added: rest timer after logging a set; countdown for timed sets that fills in the duration; timers survive locking or leaving the app.
  - Added: **Apple Watch app** — see and control the running timer, start rest or the next timed set from the wrist, tap on the wrist at zero.
- **0.5.0 — 2026-11-01** (#41)
  - Added: client intake — extended profile (DOB, emergency contact, physician, occupation, history, availability), health screening and medical clearance, NASM Overhead Squat and Single-Leg Squat assessments with measurements, liability waiver (send as PDF, mark signed, editable template in Settings), and a guided intake flow.
  - Fixed: waiver screen hang.
- **0.4.0 — 2026-11-01** (#39, #40)
  - Added: Schedule week view with week navigation; the chosen view is remembered.
  - Added: edit, cancel or delete "this session only" or "this and following" for repeating sessions; calendar stays in sync.
- **0.3.0 — 2026-10-27** (#34, #36)
  - Added: progress reports (total reps, exercise history and estimated 1RM, consistency over a chosen window, weekly volume, top exercises, PNG export and overview page); "About you" self client.
  - Changed: refreshed look and themed components, inline set table, icon dark/tinted/clear variants, larger-text accessibility fixes.
- **0.2.0 — 2026-10-26** (#2, #31, #32)
  - Added: app icon; edit and delete a session; export reminder banner; injuries and notes on the run screen; per-exercise weight units; Permissions rows; data-store backup before upgrades.
  - Changed: confirmations before destructive actions; replace-import is now reversible on failure; calendar falls back to any writable calendar.
  - Fixed: repeating series length, phantom calendar event, deleted sessions leaving sets behind, duplicate Face ID prompt, reminders for cancelled sessions, backup restore.
- **0.1.0 — 2026-07-09** (#1)
  - Added: the initial app — clients, exercise library with 34 starter exercises, workout templates, scheduling with weekly repeats and calendar, recording sessions set by set, history and progress charts, session reminders and text reminders, report sharing, JSON export and import, Face ID lock, recovery screen.

Footer compare links:
```
[Unreleased]: https://github.com/madacgrav/trainme/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/madacgrav/trainme/compare/v0.5.0...v0.6.0
... down to
[0.1.0]: https://github.com/madacgrav/trainme/releases/tag/v0.1.0
```

#### 5. Local tags
Annotated tags, created locally only and **not pushed**:
```bash
git tag -a v0.1.0 293f8c1 -m "0.1.0 development build"
git tag -a v0.2.0 6344ac6 -m "0.2.0 development build"
git tag -a v0.3.0 0c7a624 -m "0.3.0 development build"
git tag -a v0.4.0 d47fea0 -m "0.4.0 development build"
git tag -a v0.5.0 2b593fd -m "0.5.0 development build"
git tag -a v0.6.0 cc709b8 -m "0.6.0 development build"
```
If implementing in a worktree, tags are shared repo-wide, which is fine.

#### 6. Backlog
**File**: `BACKLOG.md`
**Action**: move row 34 (quick timers, #38) from the P2 table to a new "Done — #42" table. Change nothing else.

### Verification
#### Automated
- [x] TEST passes, including `bundleVersionIsSemanticAndResolved`.
- [x] WATCH passes.
- [x] `APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/TrainMe.app' -maxdepth 6 | head -1); plutil -p "$APP/Info.plist" | grep -E 'ShortVersion|CFBundleVersion|UIDeviceFamily|LSApplicationCategoryType|ITSApp'` shows `1.0.0`, `1`, `[1]`, healthcare-fitness and `false`. Repeat for `$APP/Watch/TrainMeWatch.app/Info.plist` (expect `1.0.0`, `1`).
- [x] `git tag -l 'v0.*'` lists 6 tags.

#### Manual
- [x] Read CHANGELOG.md: dates are in order, wording is user-facing, and no internal jargon such as "SchemaV3" or "WAL".

---

## Phase 2: Public docs site (privacy, support, changelog)

### Changes

#### 1. Jekyll config
**File**: `docs/_config.yml`, **create**
```yaml
title: TrainMe
description: Client, workout and session log for independent personal trainers — iPhone and Apple Watch.
theme: jekyll-theme-primer
baseurl: /trainme
url: https://madacgrav.github.io
exclude: [app-store]
```
Phase 8 depends on `exclude: [app-store]`; add it now.

#### 2. Pages (front matter `title:` and `permalink:` on each)
- `docs/index.md` (`permalink: /`)
  - Contents: a two-paragraph pitch, the app icon image (`images/icon.png`, copied from `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/p5-icon-default.png`), and links to the Guide, Privacy, Support and Changelog.
  - Wording: "Your data never leaves your iPhone unless you send it."
- `docs/privacy.md` (`permalink: /privacy/`), effective date 2026-11-01. Sections:
  1. **Summary:** TrainMe collects no data. There are no accounts, servers, analytics or ads.
  2. **What the app stores and where:** the client and session data listed in research Q4, in the app's private storage on your iPhone, protected by iOS Data Protection and optionally by Face ID.
  3. **When data leaves your iPhone (only when you choose):**
     - calendar events (client name and session notes)
     - text reminders, which you send
     - report PDF/PNG and waiver PDF, which you share
     - JSON export files you save
     - Apple Watch, which receives only timer state and the next exercise name
  4. **Notifications:** local only.
  5. **Permissions:** Calendar, Face ID and Notifications — what each is used for.
  6. **Client information:** you are responsible for getting your clients' consent and for handling their health information under the laws that apply to you. TrainMe is not a medical device and does not give medical advice.
  7. **Deleting data:** delete the app; exports you saved elsewhere are yours to delete.
  8. **Children:** not directed to children.
  9. **Changes:** posted on this page.
  10. **Contact:** madacgrav@gmail.com.
- `docs/support.md` (`permalink: /support/`)
  - Contact: email madacgrav@gmail.com, or GitHub issues at `https://github.com/madacgrav/trainme/issues`.
  - FAQ:
    - Where is my data? On your iPhone only.
    - How do I back up? Settings › Backup › "Export all data…".
    - New phone or reinstalled the app? Use "Import from file…". Without an export your data cannot be recovered.
    - Face ID failed or the app is locked? "Unlock" falls back to your passcode.
    - "TrainMe couldn't open its data store"? Try "Restore last backup" first.
    - Watch shows nothing? Open TrainMe on your iPhone; the watch needs the phone nearby.
    - Reminders not arriving? Settings › Permissions.
  - Links to the Guide.
- `docs/changelog.md` (`permalink: /changelog/`)
  - Front matter, plus a one-line intro and the full changelog.
  - Keep a single source: `scripts/sync-changelog.sh` copies `CHANGELOG.md` (minus its H1) below the front matter.

#### 3. Changelog sync script
**File**: `scripts/sync-changelog.sh`, **create**, `chmod +x`
```bash
#!/usr/bin/env bash
# Regenerates docs/changelog.md from CHANGELOG.md (single source of truth).
set -euo pipefail
cd "$(dirname "$0")/.."
{ printf -- '---\ntitle: Changelog\npermalink: /changelog/\n---\n\n'; tail -n +2 CHANGELOG.md; } > docs/changelog.md
```

#### 4. Link checker
**File**: `scripts/check-docs-links.sh`, **create**, `chmod +x`. It checks every relative markdown link and image in `docs/**/*.md` and `README.md`:
```bash
#!/usr/bin/env bash
# Fails if a relative link/image in docs/ or README.md points at a missing file.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
while IFS= read -r file; do
  dir=$(dirname "$file")
  grep -oE '\]\([^)#[:space:]]+' "$file" | sed 's/^](//' | while read -r link; do
    case "$link" in http*|mailto:*) continue ;; esac
    target="$dir/$link"
    # Pretty permalinks: "guide/scheduling/" -> guide/scheduling.md ; "/trainme/x/" -> docs/x.md
    [[ "$link" == /trainme/* ]] && target="docs/${link#/trainme/}"
    t="${target%/}"
    [[ -e "$t" || -e "$t.md" || -e "$t/index.md" ]] || { echo "BROKEN: $file -> $link"; exit 1; }
  done || fail=1
done < <(find docs -name '*.md' -not -path 'docs/app-store/*'; echo README.md)
exit $fail
```
In docs pages, write internal links as relative `.md` paths (for example `[Privacy](privacy.md)`). GitHub Pages' `jekyll-relative-links` plugin, which is on by default, rewrites them, and the checker resolves them.

### Verification
#### Automated
- [x] `scripts/sync-changelog.sh && git diff --stat docs/changelog.md` regenerates the page without error.
- [x] `scripts/check-docs-links.sh` exits 0.
- [x] `grep -c "madacgrav@gmail.com" docs/privacy.md docs/support.md` returns ≥ 1 for each.

#### Manual
- [x] Preview `docs/privacy.md` in GitHub's markdown preview or the IDE. Every outbound path in research Q4 is covered, and nothing claims cloud sync.

---

## Phase 3: In-app About section

### Changes

#### 1. AppInfo and AppLinks
**File**: `Sources/Support/AppInfo.swift`, **create**
```swift
import Foundation

/// Version text and public URLs shown in Settings › About.
enum AppInfo {
    /// "1.0.0 (1)"; tolerates a missing build or dictionary (tests, previews).
    static func versionString(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

enum AppLinks {
    private static let base = URL(string: "https://madacgrav.github.io/trainme/")!
    static let guide = base.appending(path: "guide/")
    static let privacy = base.appending(path: "privacy/")
    static let support = base.appending(path: "support/")
    static let changelog = base.appending(path: "changelog/")
    static let license = URL(string: "https://github.com/madacgrav/trainme/blob/main/LICENSE")!
}
```

#### 2. Settings section
**File**: `Sources/Features/Settings/SettingsView.swift`, **modify**. Insert after the Permissions `Section` (ends around line 123) and before `if let statusMessage`:
```swift
Section {
    LabeledContent("Version", value: AppInfo.versionString())
    Link("User guide", destination: AppLinks.guide)
    Link("What's new", destination: AppLinks.changelog)
    Link("Privacy policy", destination: AppLinks.privacy)
    Link("Support", destination: AppLinks.support)
    Link("License (GPL v3)", destination: AppLinks.license)
} header: {
    Text("About")
}
```

#### 3. Tests
**File**: `Tests/AppInfoTests.swift`, **create**
```swift
@Test func versionWithBuild() { #expect(AppInfo.versionString(["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7"]) == "1.0.0 (7)") }
@Test func versionWithoutBuild() { #expect(AppInfo.versionString(["CFBundleShortVersionString": "1.0.0"]) == "1.0.0") }
@Test func missingInfo() { #expect(AppInfo.versionString(nil) == "—") }
@Test func linksAreHTTPS() { #expect([AppLinks.guide, .privacy, .support, .changelog, .license].allSatisfy { $0.scheme == "https" }) }
```

#### 4. Changelog
Under `[Unreleased]` › Added, add: "Settings › About: version, user guide, what's new, privacy policy, support and license." Run `scripts/sync-changelog.sh`.

### Verification
#### Automated
- [x] TEST passes (AppInfoTests and the existing ArchiveRoundTripTests).

#### Manual
- [x] Simulator: Settings › scroll to the bottom › About shows "1.0.0 (1)". Tapping "Privacy policy" opens Safari at the URL; a 404 is expected until Pages is enabled.

---

## Phase 4: iPhone demo mode (DEBUG only)

**Launch contract**: `-demoData` enables demo mode. `-demoScreen <name>` picks the screen. Standard UserDefaults argument-domain flags let the script skip first-run UI without code:
- `-hasSeenBackupNotice YES` suppresses the first-run alert.
- `-lastExportAt 4102444800` (year 2100) suppresses the export banner and badge.
- `-scheduleMode week` selects week mode (key `scheduleMode`, `ScheduleViewModel.swift:31`).

The argument domain is volatile, so nothing persists. Code still forces these in demo mode as a safety net (below).

### Changes

#### 1. Launch parsing
**File**: `Sources/Support/DemoLaunch.swift`, **create**. Wrap the whole file in `#if DEBUG … #endif`.
```swift
#if DEBUG
import Foundation

enum DemoScreen: String, CaseIterable, Sendable {
    case schedule, scheduleWeek, session, clients, client, report, assessment, workouts, builder, exercises, settings
    /// RootView tab that hosts this screen.
    var tab: Int {
        switch self {
        case .schedule, .scheduleWeek, .session: 0
        case .clients, .client, .report, .assessment: 1
        case .workouts, .builder: 2
        case .exercises: 3
        case .settings: 4
        }
    }
}

struct DemoLaunch: Sendable, Equatable {
    let enabled: Bool
    let screen: DemoScreen?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        enabled = arguments.contains("-demoData")
        if let i = arguments.firstIndex(of: "-demoScreen"), arguments.indices.contains(i + 1) {
            screen = DemoScreen(rawValue: arguments[i + 1])
        } else {
            screen = nil
        }
    }

    static let current = DemoLaunch()
}
#endif
```

#### 2. Demo dataset
**File**: `Sources/Support/DemoData.swift`, **create**, `#if DEBUG`, `@MainActor enum DemoData`. It reuses the DTO → `toModel()` → `ModelContext.insert` pattern from `PreviewFixtures.container` (`Sources/Support/PreviewFixtures.swift:176-190`). Expose `static let featuredClientId` and `static let todaySessionId` so the routes can find them.

```swift
static func container(now: Date = .now, calendar: Calendar = .current) throws -> ModelContainer {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let ctx = ModelContext(container)
    exercises.forEach { ctx.insert($0.toModel()) }
    workouts.forEach { ctx.insert($0.toModel()) }
    clients.forEach { ctx.insert($0.toModel()) }
    ctx.insert(screening.toModel())                       // featured client, cleared
    assessments.forEach { ctx.insert($0.toModel()) }      // featured client, 2 (6 weeks apart)
    ctx.insert(waiverTemplate.toModel()); ctx.insert(waiverRecord.toModel()) // signed
    let (sessions, sets) = history(now: now, calendar: calendar)
    sessions.forEach { ctx.insert($0.toModel()) }
    sets.forEach { ctx.insert($0.toModel()) }
    try ctx.save()
    return container
}
```

Content:
- **exercises (12)**, fixed UUIDs:
  - strength (weight/reps/sets, lb): Barbell Back Squat, Bench Press, Deadlift, Overhead Press, Bent-Over Row, Goblet Squat, Romanian Deadlift
  - bodyweight: Push-up (reps/sets), Plank (duration, sec), Walking Lunge (reps/sets)
  - cardio: Rowing Machine (distance+duration, km)
  - mobility: Hip Flexor Stretch (duration)

  The seed importer then skips, because the count is not 0 (`SeedImporter.swift:15`).
- **workouts (4)**: "Lower Strength", "Upper Push", "Full Body Conditioning" (includes Plank 3×45 s as a timed entry), "Mobility Reset".
- **clients (6)**:
  - "Jordan Lee" — featured client, full profile, goal "Squat 225 lb by spring", injury "Old right shoulder strain — no behind-neck pressing".
  - "Priya Shah"
  - "Marcus Bell"
  - "Elena García"
  - "Tom Becker"
  - Self client "You" (`isSelf: true`)

  All phones use the `+1555…` fictional range.
- **history**:
  - Sessions for 8 past weeks: Jordan 2×/week ("Lower Strength"/"Upper Push"), Priya and Marcus 1×/week, mostly `.completed` with one `.noShow` and one `.cancelled`.
  - Each completed session gets `SetRecordDTO`s with progressive load: Jordan's back squat goes 155 → 205 lb (+5–10 lb/week) at 5×5, so the charts rise.
  - **This week**: 7 sessions across Mon–Fri. Today has 3: 7:00 completed (Priya), 9:00 scheduled (Jordan, `todaySessionId`, "Lower Strength", the first exercise has 2 logged sets), and 17:30 scheduled as part of a weekly series (Marcus).
  - Instance, planned-entry and set ids are always fresh `UUID()`s, because they are unique in the store (`PreviewFixtures.swift:94` comment).

Reuse the `SessionDTO`/`WorkoutInstanceDTO`/`PlannedEntryDTO` shapes from `PreviewFixtures.weekSessions` (`PreviewFixtures.swift:96-122`). Factor a private `func session(client:workout:start:status:)` helper inside `DemoData`; do not modify `PreviewFixtures`.

#### 3. Bootstrap
**File**: `Sources/TrainMeApp.swift`, **modify** `AppBootstrap.init`:
```swift
init() {
    #if DEBUG
    if DemoLaunch.current.enabled {
        do { state = .ready(try DemoData.container()) } catch { state = .failed(error.localizedDescription) }
        return
    }
    #endif
    // …existing body unchanged…
}
```

#### 4. Lock bypass
**File**: `Sources/Features/Lock/LockGateView.swift`, **modify**:
```swift
private var isUnlocked: Bool {
    #if DEBUG
    if DemoLaunch.current.enabled { return true }
    #endif
    return lock.isUnlocked
}
```
Use `isUnlocked` in `body`. Also skip `.task { await lock.authenticate() }` in demo mode (guard inside the task).

#### 5. RootView routing
**File**: `Sources/RootView.swift`, **modify**
- In `init(container:)`, after the existing setup:
  ```swift
  #if DEBUG
  if DemoLaunch.current.enabled { _selectedTab = State(initialValue: DemoLaunch.current.screen?.tab ?? 0) }
  #endif
  ```
- In the `.task`, wrap `await reminders.requestAuthorization()` so it is skipped in demo mode, which avoids the system prompt in screenshots. In demo mode also force `hasSeenBackupNotice = true` and set `exportDue = false`.
- For **deep screens**, replace the tab's root content in demo mode. In each `Tab`, write:
  ```swift
  Tab("Clients", …) {
      #if DEBUG
      if let demo = DemoRoute.view(for: DemoLaunch.current, tab: 1, container: container, reminders: reminders, intake: intake) { demo } else { clientList }
      #else
      clientList
      #endif
  }
  ```
  Here `clientList` etc. are the existing bodies extracted into private computed properties of RootView, with no behaviour change. This is the only refactor allowed.
- **Fallback**: if the extraction becomes awkward, apply the demo override only to tabs 0, 1 and 2.

**File**: `Sources/Support/DemoRoute.swift`, **create**, `#if DEBUG`, `@MainActor enum DemoRoute`. `static func view(for:tab:container:reminders:intake:) -> AnyView?` returns `nil` unless `screen.tab == tab` and the screen is deep. It builds:
- `.session`: `NavigationStack { SessionRunView(viewModel: SessionRunViewModel(sessionRepo:…, exerciseRepo:…, clientRepo:…, session: <todaySession DTO>, clientName: "Jordan Lee", clientPhone: …, clientInjuries: …, healthRepo: intake.health, onStatusChanged: {}), workoutRepo: …) }`. Use the same argument list as `ScheduleView.swift:99-110`. The DTO comes from `DemoData.todaySession` (a static, built with the same `now` as the container; store it when `container()` runs).
- `.client`: `NavigationStack { ClientDetailView(viewModel: ClientDetailViewModel(repo:, exerciseRepo:, sessionRepo:, reporting: SwiftDataReportingQueries(modelContainer:), reminders:, intake:, client: DemoData.featuredClient)) }`, following `ClientListView.swift:18-27`.
- `.report`: `NavigationStack { ClientReportView(viewModel: ClientReportViewModel(reporting:, exerciseRepo:, client: DemoData.featuredClient)) }`, following `ClientDetailView.swift:143-147`.
- `.assessment`: `NavigationStack { AssessmentDetailView(assessment: DemoData.assessments[0], previous: DemoData.assessments[1], weightUnit: .lb, onEdit: nil) }`, following `ClientDetailView.swift:108-113`. Check that `onEdit` is optional; if it is not, pass `{}`.
- `.builder`: `WorkoutBuilderView(workoutRepo:, exerciseRepo:, existing: DemoData.workouts[0]) {}`, following `WorkoutBuilderView.swift:181`. It already contains its own NavigationStack.
- `.scheduleWeek`: return `nil`. Week mode comes from the `-scheduleMode week` launch arg.

The deep screens have no back button in demo mode. That is accepted, because they exist only for screenshots.

- **Running timer for the `.session` shot**: in `DemoRoute`, attach `.task { timers.startRest(seconds: 90) }` using `@Environment(TimerStore.self)`. Do this inside a small `DemoSessionHost` view, so the TimerBar shows a live rest countdown.

#### 6. Tests
**File**: `Tests/DemoDataTests.swift`, **create** (the test target compiles in Debug)
```swift
@MainActor @Test func demoContainerIsPopulated() async throws {
    let c = try DemoData.container()
    let ctx = ModelContext(c)
    #expect(try ctx.fetchCount(FetchDescriptor<Client>()) == 6)
    #expect(try ctx.fetchCount(FetchDescriptor<Exercise>()) == 12)
    let done = try ctx.fetch(FetchDescriptor<Session>()).filter { $0.statusRaw == SessionStatus.completed.rawValue }
    #expect(done.count >= 20)
    #expect(try ctx.fetchCount(FetchDescriptor<SetRecord>()) >= 100)
}
@Test func parsesLaunchArguments() {
    let d = DemoLaunch(arguments: ["app", "-demoData", "-demoScreen", "report"])
    #expect(d.enabled && d.screen == .report && d.screen?.tab == 1)
    #expect(DemoLaunch(arguments: ["app"]).enabled == false)
    #expect(DemoLaunch(arguments: ["app", "-demoData", "-demoScreen"]).screen == nil)
}
```
Adjust the model property names (`statusRaw`) to match `Sources/Models/Session.swift:25-36`.

#### 7. Changelog
Under [Unreleased], add nothing; this is not user-visible.

### Verification
#### Automated
- [x] TEST passes, including DemoDataTests.
- [x] `xcodebuild -scheme TrainMe -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds.
- [x] `strings "$(find ~/Library/Developer/Xcode/DerivedData -path '*Release-iphonesimulator/TrainMe.app/TrainMe' | head -1)" | grep -c -E 'demoData|Jordan Lee'` prints `0`.

#### Manual
- [x] `xcrun simctl boot "iPhone 18 Pro Max"`, then install the Debug app.
- [x] `xcrun simctl launch booted com.madacgrav.trainme -demoData -demoScreen report -hasSeenBackupNotice YES -lastExportAt 4102444800` opens a populated, unlocked report with no alerts.
- [x] Repeat for `session` (TimerBar counting down), `client`, `assessment`, `builder`, and `schedule` with `-scheduleMode week`.
- [x] A normal launch with no args still shows the lock screen and the real data store (unchanged).

---

## Phase 5: Watch demo mode and watch App Store readiness

### Changes

#### 1. Watch demo snapshots
**File**: `Watch/WatchDemo.swift`, **create**, `#if DEBUG`
```swift
#if DEBUG
import Foundation

enum WatchDemo {
    /// nil unless launched with -demoData. -demoWatch running|idle (default running).
    static func snapshot(arguments: [String] = ProcessInfo.processInfo.arguments, now: Date = .now) -> TimerSnapshot? {
        guard arguments.contains("-demoData") else { return nil }
        let state = arguments.firstIndex(of: "-demoWatch").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "running"
        let base = TimerSnapshot(timer: nil, upNext: nil, defaultRest: TimerMath.defaultRest, quickPicks: TimerMath.quickPicks, sentAt: now)
        switch state {
        case "idle":
            var s = base
            s.upNext = UpNext(plannedEntryId: UUID(), instanceId: UUID(), exerciseName: "Plank", seconds: 45)
            return s
        default:
            var s = base
            // 90 s rest with ~62 s left at capture time.
            s.timer = ActiveTimer(id: UUID(), kind: .rest, startedAt: now.addingTimeInterval(-28), endAt: now.addingTimeInterval(62))
            return s
        }
    }
}
#endif
```
If `TimerSnapshot`/`ActiveTimer` have no memberwise init accessible from the Watch target (both live in `Shared/`, so they should), use `TimerMath.make(kind:seconds:now:)` (`Shared/Timer/TimerMath.swift:8`) for the timer.

#### 2. Watch app entry
**File**: `Watch/TrainMeWatchApp.swift`, **modify**:
```swift
@State private var model: WatchTimerModel = {
    #if DEBUG
    if let snap = WatchDemo.snapshot() { return WatchTimerModel(snapshot: snap) }
    #endif
    return WatchTimerModel()
}()
```
In `.task`, skip `model.activate()` when `WatchDemo.snapshot() != nil` (DEBUG only), so a phone snapshot can't overwrite the demo.

#### 3. Watch icon
**File**: `project.yml`, **modify** TrainMeWatch:
```yaml
    sources:
      - Watch
      - Shared
      - path: Sources/AppIcon.icon
        buildPhase: resources
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```
- **Fallback** if XcodeGen or actool rejects a shared `.icon` path: copy the bundle to `Watch/AppIcon.icon` (the same `icon.json` already declares watchOS circles, `icon.json:102-107`) and list it under `Watch` sources.
- Verify with `find <watch .app> -name 'Assets.car'` and `assetutil --info .../Assets.car | grep -i AppIcon`.

#### 4. Watch privacy manifest
Research found no `UserDefaults` or other required-reason API in `Watch/` or `Shared/` (`grep -rn UserDefaults Watch Shared` is empty). **Do not add** `Watch/PrivacyInfo.xcprivacy`. Record this decision in the Phase 5 commit message. If the grep returns hits at implementation time, add a manifest that mirrors `Sources/PrivacyInfo.xcprivacy`, with only the APIs used.

#### 5. Tests
`WatchDemo` is in the watch target, which has no test target. The WATCH build is its compile check. `TimerSnapshot` codec coverage already exists (`Tests/SyncCodecTests.swift`).

### Verification
#### Automated
- [x] WATCH passes. TEST passes.
- [x] `grep -rn UserDefaults Watch Shared` returns nothing, which confirms no manifest is needed.
- [x] The built watch app contains `Assets.car` with an AppIcon entry.

#### Manual
- [ ] Install on `Apple Watch Ultra 4 (49mm)`, then `xcrun simctl launch <watch-udid> com.madacgrav.trainme.watchkitapp -demoData -demoWatch running`. The Rest ring counts down from about 1:02.
- [ ] Run the same with `-demoWatch idle`. It shows "Plank · 45 s" plus the Rest 60/90/120 picks.
- [ ] The watch home screen shows the TrainMe icon.

---

## Phase 6: Screenshot script and App Store screenshots

### Changes

#### 1. Script
**File**: `scripts/screenshots.sh`, **create**, `chmod +x`. Outline:
```bash
#!/usr/bin/env bash
# Regenerates App Store + guide screenshots from DEBUG demo data. Usage: scripts/screenshots.sh [--dark] [--only <name>]
set -euo pipefail
cd "$(dirname "$0")/.."
PHONE="${PHONE:-iPhone 18 Pro Max}"; WATCH="${WATCH:-Apple Watch Ultra 4 (49mm)}"
APPEARANCE=light; ONLY=""
# parse --dark / --only
DERIVED=build/ScreenshotsDerivedData
xcodegen generate
xcodebuild -scheme TrainMe -configuration Debug -destination "platform=iOS Simulator,name=$PHONE" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
APP="$DERIVED/Build/Products/Debug-iphonesimulator/TrainMe.app"
WAPP="$APP/Watch/TrainMeWatch.app"
udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }
P=$(udid "$PHONE"); W=$(udid "$WATCH")
xcrun simctl boot "$P" 2>/dev/null || true; xcrun simctl bootstatus "$P" -b
xcrun simctl ui "$P" appearance "$APPEARANCE"
xcrun simctl status_bar "$P" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$P" "$APP"
ARGS=(-demoData -hasSeenBackupNotice YES -lastExportAt 4102444800)
shot() { # name screen [extra args...]
  local name=$1 screen=$2; shift 2
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && return
  xcrun simctl terminate "$P" com.madacgrav.trainme 2>/dev/null || true
  xcrun simctl launch "$P" com.madacgrav.trainme "${ARGS[@]}" -demoScreen "$screen" "$@" >/dev/null
  sleep 4
  for dir in docs/app-store/screenshots docs/guide/images; do mkdir -p "$dir"; done
  xcrun simctl io "$P" screenshot "docs/app-store/screenshots/$name${APPEARANCE/light/}.png"
}
```
`${APPEARANCE/light/}` adds no suffix for light and "dark" for dark. Use `name-dark` explicitly instead if that is clearer.

App Store set (iPhone):
| file | screen | extra |
|---|---|---|
| `01-schedule-week` | `schedule` | `-scheduleMode week` |
| `02-session-timer` | `session` | |
| `03-client-detail` | `client` | |
| `04-progress-report` | `report` | |
| `05-assessment` | `assessment` | |
| `06-workout-builder` | `builder` | |

Guide-only extras, written to `docs/guide/images/`:
- `schedule-day` (`schedule`, `-scheduleMode day`)
- `clients` (`clients`)
- `workouts` (`workouts`)
- `exercises` (`exercises`)
- `settings` (`settings`)
- copies of the six App Store shots

Watch section:
- Boot `$W`.
- Pair if the phone and watch are not paired: `xcrun simctl pair "$W" "$P"` (ignore the error if already paired).
- `xcrun simctl install "$W" "$WAPP"`.
- Launch with `-demoData -demoWatch running`, then `sleep 3`, then screenshot to `w1-timer-running.png`. Repeat for `idle` → `w2-quick-start.png`. Copy both to `docs/guide/images/`.

Finish with:
- `xcrun simctl status_bar "$P" clear`
- a size report: `sips -g pixelWidth -g pixelHeight docs/app-store/screenshots/*.png`

#### 2. Output and git
- Commit the generated PNGs; they are the deliverable. Add `build/ScreenshotsDerivedData` to `.gitignore` if `build/` is not already ignored. Check first with `git check-ignore build`.
- **Accepted App Store sizes**:
  - iPhone 6.9": 1320×2868 (or 1290×2796).
  - Watch: 422×514, 410×502, 416×496, 396×484 or 368×448.

  If the simulator's native size is not in this list, the script exits non-zero, printing the actual size. In that case set `PHONE=` or `WATCH=` to a simulator that matches, using `xcrun simctl list devicetypes`.

Size check at the end of the script:
```bash
for f in docs/app-store/screenshots/0*.png; do s=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{print $2}' | paste -sd x -); [[ "$s" =~ ^(1320x2868|1290x2796)$ ]] || { echo "BAD SIZE $f $s"; exit 1; }; done
for f in docs/app-store/screenshots/w*.png; do s=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{print $2}' | paste -sd x -); [[ "$s" =~ ^(422x514|410x502|416x496|396x484|368x448)$ ]] || { echo "BAD SIZE $f $s"; exit 1; }; done
```

### Verification
#### Automated
- [x] `scripts/screenshots.sh` exits 0, which includes the size checks.
- [x] `ls docs/app-store/screenshots | wc -l` returns ≥ 8, and `ls docs/guide/images | wc -l` returns ≥ 13.

#### Manual
- [x] Open each PNG. Check that:
  - the data is populated
  - no system or app alerts appear
  - the status bar shows 9:41 with a full battery
  - the session shot shows the TimerBar counting
  - the charts in the report shot rise
  - no `Sam Rivera` preview data appears
  - fictional phone numbers only

---

## Phase 7: User guide and README

### Changes

#### 1. Guide pages
Location: `docs/guide/`, **create**. Each page has front matter `title:`, a one-line intro, then numbered "How to" steps. Images use relative paths (`![Week view](images/01-schedule-week.png){: width="320"}`). Quote labels in backticks exactly as they appear in the code, with the references from research Q1.

| file | covers (labels to quote) |
|---|---|
| `index.md` | TOC linking all pages; "TrainMe at a glance" — 5 tabs: `Schedule`, `Clients`, `Workouts`, `Exercises`, `Settings` |
| `getting-started.md` | Face ID (`Unlock`), the first-run alert "Your data lives only on this iPhone" with `Got it` / `Add yourself as a client`, the 34 starter exercises, permissions prompts |
| `clients-and-intake.md` | `Add`, `New Client` fields, `Start intake for …?`, intake steps (`Choose sections`…`Review`), `Next`/`Done`/`Back`, `More actions` › `Edit`/`Start intake`/`Archive`, search |
| `health-assessments-waivers.md` | `New screening` (not a diagnosis; clearance), `New assessment` (Overhead Squat, Single Leg Squat, R/L taps, `Changes since …`), `Send waiver…`, `Mark signed & returned…`, Settings › `Liability waiver template` (ALL CAPS headings, `!!` bold, `#` hidden) |
| `workouts-and-exercises.md` | Workout builder (`Workout name`, `Add exercise`, `Targets`, reorder, swipe `Duplicate`/`Delete`), exercises (`Category` filter, `Tracked metrics`, `Default unit`, `Custom`) |
| `scheduling.md` | `View` Day/Week, `Previous week`/`Next week`/`Today`, `New Session` (`Client`, `Starts`, `Duration`, `Workouts`, `Repeats weekly`, `For N weeks`, `Add to iPhone calendar`), editing repeating sessions (`This session only` / `This and following sessions`) |
| `running-a-session.md` | Health & limitations, `Session notes`, set table (Prev, tap a value, `Log set`, delete a set), rest timer (`Rest` menu, `+N s`, `Skip`, `Change`), timed sets (`Start N s countdown`), `Mark Completed`/`Cancelled`/`No-show`, `Text reminder` |
| `apple-watch.md` | Install via the Watch app; running timer `+N s`/`Skip`; quick start (up-next button, `Rest N s`); wrist tap at zero; needs the iPhone nearby |
| `reports.md` | `View progress`, `Window`, Consistency/Weekly volume/Top exercises, exercise detail (Personal best, Estimated 1RM (Epley)), `Share report` › `Share PDF`/`Share PNG`; "Not enough data yet" explained |
| `backup-and-restore.md` | `Export all data…`, the `!` badge and "Back up your data" banner, `Import from file…` › `Merge with existing data` / `Replace ALL data`, new phone/reinstall (paid app re-download keeps the purchase, not the data) |
| `settings.md` | Units, `Default rest`, Permissions + `Open Settings`, About |
| `troubleshooting.md` | Locked out, recovery screen (`Restore last backup`, `Start fresh…`), "Couldn't load the exercise library", calendar/notification issues, watch not updating; link to Support |

#### 2. README
**File**: `README.md`, **modify**. Replace lines 5–8 (the summary) with:
- A product paragraph that includes the Apple Watch timer.
- A "Docs" bullet list: User guide, Privacy, Support, Changelog (`CHANGELOG.md`), License (GPL v3, `LICENSE`).

Leave the Building/Requirements/Layout sections. Add `docs/` and `scripts/` to the layout list (README:57-67).

#### 3. Label check script
**File**: `scripts/check-guide-labels.sh`, **create**, `chmod +x`
```bash
#!/usr/bin/env bash
# Every `backticked` UI label in docs/guide must appear as a string literal in Sources/ or Watch/.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=0
grep -ohE '`[^`]+`' docs/guide/*.md | tr -d '`' | sort -u | while read -r label; do
  # strip "N"/"…" placeholders: compare the literal prefix before a placeholder
  probe=$(printf '%s' "$label" | sed -E 's/ ?(N|…|<[^>]+>).*$//')
  [[ ${#probe} -lt 3 ]] && continue
  grep -rqF "\"$probe" Sources Watch || { echo "MISSING LABEL: $label"; missing=1; }
done
exit $missing
```
Use backticks only for UI labels in guide pages. Use *italics* for everything else.

#### 4. Changelog
Under [Unreleased] › Added: "User guide, privacy policy and support pages at madacgrav.github.io/trainme." Run `scripts/sync-changelog.sh`.

### Verification
#### Automated
- [x] `scripts/check-docs-links.sh` exits 0, which covers images, cross-links and README.
- [x] `scripts/check-guide-labels.sh` exits 0. Fix the guide wording, not the app, on a miss.

#### Manual
- [ ] Read the guide start to finish against the app running with `-demoData`. Every step works as described.

---

## Phase 8: App Store submission kit

### Changes

#### 1. Metadata
**File**: `docs/app-store/metadata.md`, **create**. Each field is an H2 followed by one fenced ```text block, which the checker parses. Fields and limits:

| field | limit | content |
|---|---|---|
| Name | 30 | `TrainMe` |
| Subtitle | 30 | `Client log for personal trainers` |
| Promotional Text | 170 | One line: schedule, record sets, rest timer on your wrist, progress reports — all on your iPhone. |
| Description | 4000 | Intro (who it's for); feature blocks matching the guide headings; "Private by design" (no account, no cloud, no tracking; export for backup); Apple Watch; note "TrainMe is a record-keeping tool and does not provide medical advice." |
| Keywords | 100 | `personal trainer,client,workout log,PT,fitness coach,sessions,NASM,assessment,rest timer,progress` (trim to ≤100) |
| Support URL | — | `https://madacgrav.github.io/trainme/support/` |
| Marketing URL | — | `https://madacgrav.github.io/trainme/` |
| Privacy Policy URL | — | `https://madacgrav.github.io/trainme/privacy/` |
| Copyright | — | `2026 Adam (madacgrav)` — **owner to replace with legal name** |
| Primary / Secondary Category | — | Health & Fitness / Business |
| Price | — | USD 0.99 (paid up front, no in-app purchases) |
| Age Rating answers | — | All "None"; Medical/Treatment Information: "None" (the app records the trainer's own notes and gives no advice); Unrestricted Web Access: No → **4+** |
| App Privacy | — | "Data Not Collected" |
| Review Notes | 4000 | No login. All data is local. To see a populated app, import `Tests/Fixtures/export-v2.json`, attached via Settings › Backup › "Import from file…", or add a client. Face ID falls back to the passcode. The Apple Watch app mirrors the rest timer started on iPhone by logging a set in a session. |
| Screenshot captions | — | One line per `0N-*.png` and `wN-*.png` |

#### 2. What's New
**File**: `docs/app-store/whats-new/1.0.0.md`, **create**. Fenced text, ≤ 4000 characters: "First release on the App Store." plus a 5-bullet highlight summary drawn from CHANGELOG 0.1.0–0.6.0.

#### 3. Checklist
**File**: `docs/app-store/checklist.md`, **create**. Ordered `- [ ]` owner steps:
1. **Licence decision:** GPL v3 vs App Store terms (keep the GPL and accept the risk, dual-license, or relicense; this is the owner's call).
2. Replace the copyright legal name in `metadata.md`.
3. Push tags: `git push origin --tags`.
4. Enable GitHub Pages: repo Settings › Pages › Deploy from branch `main`, folder `/docs`. Confirm the four URLs load.
5. App Store Connect › Agreements: Paid Apps Agreement, tax forms and banking.
6. Create the app record (bundle `com.madacgrav.trainme`, SKU `trainme-ios`, primary language English (US)).
7. Pricing $0.99, all territories.
8. Fill in the metadata and upload screenshots: 6.9" iPhone set and Apple Watch set.
9. App Privacy: Data Not Collected. Age rating questionnaire.
10. In Xcode, Archive (Release, generic iOS device), then Validate, then Distribute to App Store Connect.
11. Attach the build, add review notes and the `export-v2.json` attachment, then Submit for Review.
12. After approval: tag `v1.0.0` on the release commit, move `[Unreleased]` to `[1.0.0] — <date>` in CHANGELOG, then run `scripts/sync-changelog.sh`.
13. For each later release, bump `MARKETING_VERSION` (semver) and increase `CURRENT_PROJECT_VERSION` in `project.yml`, add the CHANGELOG entry and `whats-new/<v>.md`, and re-run `scripts/screenshots.sh` if the UI changed.

#### 4. Length checker
**File**: `scripts/check-metadata-lengths.sh`, **create**, `chmod +x`. It uses an awk state machine: when it sees `## <Field>`, it captures the next fenced block, counts characters with `wc -m`, and compares against this map:
```bash
declare -A LIMIT=([Name]=30 [Subtitle]=30 ["Promotional Text"]=170 [Description]=4000 [Keywords]=100 ["Review Notes"]=4000)
```
macOS ships bash 3.2, which has no associative arrays. Use `case "$field" in Name|Subtitle) max=30;; …` instead. Also check `docs/app-store/whats-new/*.md` ≤ 4000. Exit 1 on any overflow, printing the field, its length and the limit.

#### 5. Config
`docs/_config.yml` already has `exclude: [app-store]` from Phase 2. Verify it is still there.

### Verification
#### Automated
- [ ] `scripts/check-metadata-lengths.sh` exits 0.
- [ ] `scripts/check-docs-links.sh` exits 0 (`app-store/` is excluded from the check).
- [ ] TEST and WATCH both still pass, as a final regression.

#### Manual
- [ ] Read `metadata.md` as a buyer would. The description matches the app's actual features, and nothing claims iCloud, iPad, or medical advice.
- [ ] The checklist covers every owner action in design.md "What We're NOT Doing" and "Open Risks".

---

## Deviations from structure.md
- **Phase 2:** added `scripts/sync-changelog.sh`, which keeps `docs/changelog.md` generated from the root `CHANGELOG.md` so there is one source.
- **Phase 4:**
  - Added `Sources/Support/DemoRoute.swift`.
  - Deep screens are shown as the tab's root inside a NavigationStack instead of being pushed. The app uses closure-based `NavigationLink`s (`ClientListView.swift:18`, `ScheduleView.swift:99`) with no `NavigationPath`, so injecting a path would mean changing every feature view.
  - First-run alert, export banner and week mode are suppressed through the UserDefaults launch-argument domain rather than new code paths.
- **Phase 5:** the watch privacy manifest is resolved as **not needed** (no required-reason APIs in `Watch/` or `Shared/`).
- **Phase 6:** simulators are pinned to the ones installed here (`iPhone 18 Pro Max`, `Apple Watch Ultra 4 (49mm)`) and can be overridden with env vars.
- **Phase 7:** added `scripts/check-guide-labels.sh`, which implements the structure's "label spot-check".
