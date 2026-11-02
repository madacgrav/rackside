# Design Discussion

Decisions below use the recommended options; the user said "use your best guess" (2026-11-01).

## Current State
- **No user docs.** README is a developer build guide (`README.md:10-67`); PRD is a 2026-07 draft that predates the watch app and timers (`PRD.md:3-6`). No About/Help screen; in-app guidance exists only as Form footers and alerts (`SettingsView.swift:63,83,105,122`, `RootView.swift:76-85`).
- **No App Store materials.** No privacy policy or support URL (PRD flags the need, `PRD.md:187`); no `LSApplicationCategoryType`; no metadata, keywords, or review notes anywhere.
- **Versioning never used.** iOS version is a literal `1.0`/`1` in `Sources/Info.plist:17-20`; watch has its own `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml:42-43`. No git tags. Only runtime read is the export envelope (`Services/Archive/DataArchive.swift:46`).
- **History exists only as PRs.** 10 user-visible merges #1–#42 (research Q6 table) plus SchemaV1→V3.
- **Device family implicit.** `project.yml` sets none; stale generated project shows iPhone+iPad; app is portrait-only with no iPad key (`Info.plist:23-26`).
- **No reproducible screenshot path.** No launch args, `#if DEBUG`, demo data or UI tests (research Q5). Representative data lives only in `Sources/Support/PreviewFixtures.swift` (one client, 156-190). 43 prior screenshots were hand-captured via `xcrun simctl` (`thoughts/qrspi/2026-10-26-ui-refresh-and-icon/plan.md:17-25`). No watch screenshots.
- **Privacy posture is clean.** No network, SDKs, analytics, CloudKit; manifest declares no collected data (`Sources/PrivacyInfo.xcprivacy:5-21`); all outbound paths are user-initiated sheets (research Q4). Watch target has no privacy manifest and no explicit app icon (`project.yml:29-43`).
- Repo `madacgrav/trainme` is **public**; GitHub Pages is **not enabled** (API 404).

## Desired End State
1. `docs/` folder, published by GitHub Pages from `main:/docs`, containing:
   - `index.md` — landing page (what TrainMe is, links).
   - `guide/` — user guide: Getting started (first launch, lock, backup notice, "About you"), Clients & intake, Health screening/assessments/waiver, Workouts & exercises, Scheduling (day/week, repeating sessions, calendar), Running a session (set table, timers), Apple Watch timers, Progress reports & sharing, Backup/export/import, Settings & permissions, FAQ/troubleshooting (recovery screen, Face ID). Each page embeds screenshots.
   - `privacy.md` — privacy policy (on-device only, no collection, user-initiated sharing, trainer's responsibility for client data).
   - `support.md` — contact `madacgrav@gmail.com`, FAQ links, how to report a bug (GitHub issues).
   - `CHANGELOG.md` at repo root (Keep a Changelog format), mirrored/linked from docs.
2. `docs/app-store/` — submission kit, not published as nav pages:
   - `metadata.md` — name, subtitle (≤30), promo text (≤170), description (≤4000), keywords (≤100), category, age rating answers, price, URLs, copyright, review notes (no login; how to see data — e.g. enable demo via import of a sample file), App Privacy answers ("Data Not Collected").
   - `whats-new/<version>.md` — release notes per version (≤4000), sourced from CHANGELOG.
   - `screenshots/` — final PNGs at App Store sizes, captions per shot.
   - `checklist.md` — manual App Store Connect steps (enable Pages, Paid Apps Agreement + tax/banking, set price $0.99, create app record, upload, export compliance = no encryption beyond exempt, etc.).
3. **Single version source**: `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` set once at project level in `project.yml`; `Info.plist` references `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`. First store release = **1.0.0 (build N)**. Git tags `v0.1.0`…`v0.6.0` on historical merges and `v1.0.0` on release.
4. **iPhone-only**: `TARGETED_DEVICE_FAMILY: "1"` on the iOS target; `LSApplicationCategoryType = public.app-category.healthcare-fitness`; watch target gets the app icon.
5. **Debug-only demo data**: launch argument `-demoData` (compiled under `#if DEBUG`) builds an in-memory store seeded with a realistic multi-client dataset; watch preview state driven the same way. A script `scripts/screenshots.sh` boots iPhone 17 Pro Max (6.9") and an Apple Watch Ultra/Series simulator, launches with `-demoData`, sets appearance, navigates via deep state (see Decision 5), and saves PNGs to `docs/app-store/screenshots/`.
6. **About section** at the bottom of Settings: Version x.y.z (build), links to User Guide, Privacy Policy, Support, What's New (changelog), License (GPL v3).
7. README updated: one-paragraph product description, links to docs, changelog, and license; mentions watch app.

**Verification**: Pages site renders at `https://madacgrav.github.io/trainme/` with working links; App Store metadata fields pass length limits (script or manual count); `xcodebuild` + tests still pass in CI; Release build contains no demo-data code (`#if DEBUG`); screenshots exist at 1320×2868 (iPhone 6.9") and watch size (e.g. 422×514 Ultra); Settings › About shows `1.0.0 (N)`; exported JSON `appVersion` reads `1.0.0`.

## Patterns to Follow
- **XcodeGen is source of truth** — edit `project.yml`, never the git-ignored `.xcodeproj` (`.gitignore:11`). Watch already uses build-setting versions (`project.yml:42-43`); extend that to project level.
- **Sample data via DTO → model insert**, as `PreviewFixtures.container(seedingWeek:)` does (`Sources/Support/PreviewFixtures.swift:176-190`) on an in-memory container (`Persistence/PersistenceController.swift:8-23`). Demo data should reuse this path, expand the fixture set, not invent a new persistence route.
- **Settings sections are `Section` + footer** (`SettingsView.swift:55-123`); `PermissionRow` + `Link("Open Settings")` (225-239) is the model for About rows with `Link`.
- **Screenshot capture via `xcrun simctl`** — `ui booted appearance`, `io booted screenshot` (`thoughts/qrspi/2026-10-26-ui-refresh-and-icon/plan.md:17-25`); naming `<n>-<screen>-<variant>.png`.
- **Copy tone**: plain, second person, honest about limits — match existing footers ("Your data lives only on this iPhone…", `SettingsView.swift:105`; "This screening is not a diagnosis", `HealthScreeningEditView.swift:68`). Guide screen/button names must match code labels exactly (research Q1).
- **Changelog content from research Q6**; user-facing wording only, no commit hashes or internal refactors in What's New.
- **Do NOT follow**: hard-coded plist version literals (`Info.plist:17-20`); the stale on-disk `.xcodeproj` as a reference for settings; PRD/README claims that omit the watch app; BACKLOG row 34 (timers) still listed open.

## Design Decisions
1. **Version history**: retroactive pre-release versions mapped to merges, first public release 1.0.0 —
   - 0.1.0 (2026-07-09) #1 initial app (+ `ac5a23f` lock fix)
   - 0.2.0 (2026-10-26) #2, #31, #32 — fixes, icon, safer import, permissions (SchemaV1)
   - 0.3.0 (2026-10-27) #34, #36 — reporting, UI refresh, "About you" (SchemaV2)
   - 0.4.0 (2026-11-01) #39, #40 — repeating-session edits, week view
   - 0.5.0 (2026-11-01) #41 — client intake (SchemaV3)
   - 0.6.0 (2026-11-02) #42 — timers + Apple Watch app
   - 1.0.0 (unreleased) — docs, About, demo data, iPhone-only, category
   Why: keeps full history readable without claiming public releases that never existed. Tag historical merges so the changelog links resolve.
2. **Versioning mechanics**: Semantic versioning; `MARKETING_VERSION` project-level, `CURRENT_PROJECT_VERSION` monotonically increasing integer per upload. Changelog follows Keep a Changelog sections (Added/Changed/Fixed) with an `[Unreleased]` head. Why: one place to bump; both targets must match for watch-companion validation.
3. **Device family**: iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`). Why: portrait-only phone UI; avoids 13" iPad screenshots and iPad review risk.
4. **Docs hosting**: markdown in `docs/`, GitHub Pages with default Jekyll theme (no custom build). Why: repo is public; free stable URLs for required Privacy/Support URLs; versioned with code. Enabling Pages is a manual repo-settings step for the owner.
5. **Screenshots**: `#if DEBUG` `-demoData` launch argument + `scripts/screenshots.sh`. To reach deep screens without UI tests, the flag also accepts `-demoScreen <name>` that sets the initial tab/route (e.g. `schedule`, `session`, `client`, `report`, `intake`, `builder`). Watch: `-demoData` on the watch sets a running-timer snapshot. Captions overlaid? **No** — raw screenshots with captions in `metadata.md` (framing is optional later). Set: 6 iPhone shots (Schedule week, Session run w/ timer, Client detail, Progress report, Intake/assessment, Workout builder) light mode; 2–3 watch shots. Guide reuses the same images plus a few extras.
6. **About in Settings**: new last section "About" with version/build read from `Bundle.main` and `Link` rows to the Pages URLs + changelog + license. Why: reviewers and users need support/privacy access; shows version.
7. **App Store listing defaults**: Name "TrainMe"; subtitle "Personal trainer client log" (draft); primary category Health & Fitness, secondary Business; price **$0.99 USD** (paid up-front, no in-app purchases; requires the Paid Apps Agreement plus tax and banking set up in App Store Connect — listed in `checklist.md`); age rating 4+ (no objectionable content; medical/treatment info: none — app records but doesn't provide medical advice → answer "None"/"Infrequent" reviewed at submission); App Privacy "Data Not Collected"; export compliance: uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO` added to Info.plist); support email madacgrav@gmail.com; copyright "© 2026 Adam (madacgrav)" pending owner's legal name.
8. **Privacy policy scope**: covers the app (no collection) and states the trainer is responsible for client consent and data handled on their device; mentions calendar, notifications, SMS, share sheet, exports and watch sync behavior from research Q4.
9. **Watch app parity**: add app icon to watch target and a watch `PrivacyInfo.xcprivacy` if UserDefaults is used there (verify). Why: App Store validation for embedded watch app.

## What We're NOT Doing
- No iPad support or iPad screenshots.
- No UI test target, fastlane, or CI screenshot automation (script is run manually).
- No framed/marketing screenshots, app preview videos, or localization (English only).
- No custom website theme, domain, or static-site generator beyond Pages' default Jekyll.
- No functional feature changes beyond About section, demo-data flag, plist/project settings.
- Not submitting to App Store Connect, creating the app record, enabling Pages, or pushing tags — those are documented as owner steps (tags created locally only if asked).
- No updates to PRD.md content beyond maybe a pointer; BACKLOG cleanup only for row 34 status.
- No in-app help screens or onboarding tour.

## Open Risks
- **`-demoScreen` routing** may need small hooks into `RootView` tab selection and navigation paths that don't exist today (`RootView.swift:31`); if deep routes are invasive, fall back to manual taps for 1–2 shots.
- **Watch screenshot sizes/devices** depend on installed simulator runtimes; verify available devices with `xcrun simctl list`.
- **Watch icon**: Icon Composer `.icon` declares watchOS circles (`AppIcon.icon/icon.json:102-107`) but watch target doesn't include it; behavior under XcodeGen unverified.
- **Lock gate** will block screenshots on simulator (biometrics-only, `AppLock.swift:28`); demo mode must bypass or auto-unlock in DEBUG only.
- **Version unification** may surface validation errors if iOS and watch builds differ; must regenerate project and build both.
- **Health-related App Review** (Guideline 5.1.1/1.4.1): app stores client health screening data; privacy policy and review notes must explain it's trainer-entered, on-device, not medical advice.
- **Legal name for copyright / GPL compatibility with App Store** distribution (GPLv3 and App Store terms are a known conflict) — owner decision; flagged in checklist, not resolved here.
- **Paid app**: the app can't go on sale until the Paid Apps Agreement is active, which can take days. A paid app also has no free trial, so the description and screenshots carry more weight. Data stays on the device, so a user who re-downloads gets the app again but not their data; the guide and support FAQ must say so.
- Retroactive tags on old merges rewrite nothing but are visible publicly once pushed.
