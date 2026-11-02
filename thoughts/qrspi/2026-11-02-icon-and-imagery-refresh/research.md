# Research Findings

Paths are relative to the repo root. `F/` = `Sources/Features/`.

## Q1: How is the app icon built, and how do the default, dark, clear, and tinted variants derive from the layers?

### Findings
- The icon is a hand-authored Icon Composer bundle: `Sources/AppIcon.icon/icon.json` plus five SVGs in `Sources/AppIcon.icon/Assets/`. No `AppIcon.appiconset` exists and no icon-generating script exists.
- Top level: `"fill": "system-light"` (`icon.json:2`) with one fill specialization, `dark → system-dark` (`icon.json:3-8`). `supported-platforms`: `circles: ["watchOS"]`, `squares: "shared"` (`icon.json:102-107`).
- Two groups, foreground first in the file (`icon.json:10-65`), background second (`icon.json:66-100`):
  - **Foreground group** settings: `shadow {layer-color, opacity 0.5}` (`:56-59`), `specular: true` (`:60`), `translucency {enabled, 0.2}` (`:61-64`), `blur-material: null`.
    - Layer `dumbbell` (`:13-29`): `glass: true`; single image `dumbbell.svg` for all appearances (`:16-20`); scale 0.78, translation [0, 20] (`:22-28`).
    - Layer `rising line` (`:30-54`): `glass: true`; specializations default `line.svg`, dark `line.svg`, tinted `line-mono.svg` (`:33-45`); scale 0.82, translation [0, -60] (`:47-53`).
  - **Background group**: layer `background` (`:69-89`), `glass: false`; specializations default `background.svg`, dark `background-dark.svg` (`:72-80`); scale 1, no translation. Group has shadow opacity 0, `specular: false`, translucency disabled (`:91-99`).
- SVG contents (all `viewBox="0 0 1024 1024"`):
  - `background.svg:3-8`: diagonal linearGradient (0,0)→(1,1), stops `#0F766E` → `#3730A3`, one full-bleed rect.
  - `background-dark.svg:4-5`: same structure, stops `#042F2E` → `#1E1B4B`.
  - `dumbbell.svg:1-6`: root `fill="#FFFFFF"`; five rounded rects: bar (312,484 400×56 rx28), inner plates (194/724, 380 106×264 rx30), outer plates (120/842, 424 62×176 rx22).
  - `line.svg:2-4`: polyline `176,700 392,560 560,616 848,328`, stroke `#F59E0B`, stroke-width 104, round caps/joins; end circle (848,328) r72 fill `#F59E0B`.
  - `line-mono.svg`: identical geometry, stroke and fill `#FFFFFF`.
- Appearance derivation:
  - **Default**: teal→indigo gradient, white glass dumbbell, amber glass line.
  - **Dark**: fill → `system-dark`; background → `background-dark.svg`; dumbbell unchanged; line explicitly stays amber (`icon.json:38-39`).
  - **Tinted**: only the line has a tinted entry (`line-mono.svg`, `:41-44`); background and dumbbell fall through to defaults.
  - **Clear**: no `clear` key anywhere in `icon.json`; the system derives it. No `blend-mode`, per-layer `opacity`, or per-appearance fill override exists beyond the dark fill at `:3-8`.
- Wiring (`project.yml`): iOS target `TrainMe` has `sources: [Sources, Shared]` (`:17`) so the `.icon` bundle is picked up implicitly; `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (`:25`), `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` (`:26`). Watch target `TrainMeWatch` lists `Watch`, `Shared`, and an explicit `{path: Sources/AppIcon.icon, buildPhase: resources}` (`:35-39`) with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (`:42`) and no accent color setting.
- `docs/images/icon.png` is a 196×196 PNG, referenced once at `docs/index.md:6` (`<img src="images/icon.png" ... width="96">`). Nothing generates it.
- Rendered variant captures exist: `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/p5-icon-{default,dark,tinted,clear}.png`.

## Q2: What color assets are defined, what light/dark values do they hold, and how does Theme.swift expose them?

### Findings
- `Sources/Assets.xcassets/` is the only asset catalog. It contains nine colorsets and no image or gradient assets. Each `Contents.json` has a universal (light) entry at `:3-14` and a `luminosity: dark` entry at `:15-32`, sRGB, alpha 1.

| Colorset | Light | Dark |
|---|---|---|
| AccentColor | #D97706 | #F59E0B |
| BrandPrimary | #0F766E | #2DD4BF |
| BrandSecondary | #3730A3 | #818CF8 |
| Success | #15803D | #4ADE80 |
| Warning | #C2410C | #FB923C |
| Danger | #DC2626 | #F87171 |
| PersonalBest | #A16207 | #FACC15 |
| Surface | #F2F2F7 | #0B1211 |
| SurfaceRaised | #FFFFFF | #152321 |

- Light BrandPrimary/BrandSecondary equal the `background.svg` gradient stops; dark AccentColor equals the `line.svg` stroke.
- `Sources/Support/Theme.swift`: `enum Theme` (`:4`), doc comment "Single source of visual identity. Views reference roles, never raw colors." (`:3`).
  - `Theme.Colors` (`:5-15`): nine `static let` values, each `Color("<AssetName>")` (`:6-14`).
  - `Theme.Fonts` (`:17-24`): `display(_ style:)` = `.system(style, design: .rounded, weight: .semibold)` (`:19-20`); `numeric` = `.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()` (`:23`).
  - `Theme.Spacing` xs/sm/md/lg = 4/8/12/20 (`:26-31`); `Theme.Radius.row` = 12 (`:33-35`).
  - View helpers (`:38-49`): `themedScreen()` = `scrollContentBackground(.hidden).background(Theme.Colors.surface)` (`:41-42`); `themedRows()` = `listRowBackground(Theme.Colors.surfaceRaised)` (`:47`).
- No gradient definitions exist in Theme.swift or anywhere in `Sources/` (`Gradient`/`LinearGradient` match nothing). The teal→indigo gradient lives only in the icon SVGs.

## Q3: Where are theme colors and gradients consumed in iOS views, and which components carry the most visual weight?

### Findings
- Direct `Theme.Colors.*` reference counts (excluding definitions): warning 12, success 6, accent 5, danger 5, surfaceRaised 4, surface 2, brandPrimary 2, personalBest 2, brandSecondary 1.
- **accent**: `Sources/RootView.swift:113` (`.tint` on the whole TabView); `F/Timer/TimerBar.swift:53` (ProgressView tint); `F/Session/SetTableView.swift:131` (focused metric cell, `.opacity(0.18)`); `F/Assessments/CompensationGrid.swift:32` and `F/Schedule/SessionEditView.swift:137` (toggle tints, else `Color.secondary`).
- **brandPrimary / brandSecondary / personalBest** are used only in charts: `F/Reports/ClientReportView.swift:129` (LineMark), `:136`/`:140` (PointMark + rule in personalBest), `:184` (`chartForegroundStyleScale(["lb": brandPrimary, "kg": brandSecondary])`). `ExerciseReportView.swift` reuses the same chart views; `Sources/Services/ReportExporter.swift:85-123` renders them for export.
- **warning** sites: `F/Session/SessionRunView.swift:55,60`; `F/Health/ClearanceBadge.swift:11`; `ClientReportView.swift:39`; `F/Assessments/AssessmentDetailView.swift:27`; `F/Waiver/ClientWaiverSection.swift:83`; `F/Waiver/WaiverTemplateEditView.swift:23`; `F/Components/StatusChip.swift:23`; `F/Schedule/ScheduleView.swift:17` and `:35` (banner background `.opacity(0.12)`); `F/Clients/ClientDetailView.swift:82`; `Sources/TrainMeApp.swift:120` (HeroScreen tint).
- **success** sites: `SessionRunView.swift:133`; `SetTableView.swift:101,105` (`.opacity(0.10)` logged-row background); `AssessmentDetailView.swift:23`; `ClientWaiverSection.swift:86`; `StatusChip.swift:21`.
- **danger** sites: `F/Components/ErrorBanner.swift:11`; `ClientWaiverSection.swift:23`; `WaiverTemplateEditView.swift:37`; `F/Clients/ClientEditView.swift:67,110`.
- **surface / surfaceRaised** mostly flow through helpers: `themedScreen()` has 13 call sites (WorkoutListView:41, SessionRunView:128, AssessmentDetailView:70, SetTableView:356, WaiverTemplateEditView:43, SettingsView:142, ScheduleView:61,150, ClientReportView:68, ExerciseReportView:44, ClientDetailView:159, ClientListView:46, ExerciseListView:34). `themedRows()` has 21 call sites, 10 of them in ClientDetailView. Direct uses: `HeroScreen.swift:45`, `SetTableView.swift:131`, `WaiverTemplateEditView.swift:30`, `MetricStepper.swift:19`.
- Form screens without `themedScreen()`: ClientEditView, SessionEditView, ExerciseEditView, WorkoutBuilderView, HealthScreeningEditView, AssessmentEditView, IntakeFlowView.
- Component rendering:
  - `StatusChip.swift:12-25`: Capsule, `spec.color.opacity(0.18)` background, `spec.color` foreground, `.font(.caption.weight(.semibold))`. Completed=success, Cancelled=`Color.secondary`, No-show=warning, `.scheduled` renders nothing.
  - `ErrorBanner.swift:10-11`: `Label(message, systemImage: "exclamationmark.octagon.fill").foregroundStyle(Theme.Colors.danger)`; used in 14 views.
  - `ClearanceBadge.swift:9-20`: only `.needed` is colored (warning); the other three states use `.secondary`.
  - `IconButton.swift:8-24`: `.labelStyle(.iconOnly)`, `.buttonStyle(.plain)`, default tint `HierarchicalShapeStyle.secondary`, 44pt min frame. 5 call sites.
  - `TimerBar.swift:16`: `.background(.bar)` material; buttons are system `.bordered`.
  - `HeroScreen.swift:24-46`: `Image(systemName:)` at `@ScaledMetric` 44 (`:26-27`), `.foregroundStyle(tint)` default `.secondary`, title in `Theme.Fonts.display(.title2)`, `.borderedProminent` button, `.background(Theme.Colors.surface)` (`:45`). Two callers: `LockGateView.swift:46` ("lock.fill") and `TrainMeApp.swift:116` ("exclamationmark.triangle.fill", warning tint).
  - `EmptyState.swift:10-20`: `ContentUnavailableView { Label(title, systemImage:) }` with no color code. Callers: WorkoutListView:38, ScheduleView:58, ExerciseListView:31, ClientListView:37.
  - `RootView.swift:60-113`: five tabs, `.tint(Theme.Colors.accent)` (`:113`), `.fontDesign(.rounded)` (`:112`), `.tabBarMinimizeBehavior(.onScrollDown)` (`:111`), Settings `.badge` (`:109`).
- Components with no color at all: EmptyState, TitleCaptionRow, ShareReportMenu, ActivityShareSheet. MetricStepper uses only surfaceRaised.
- Hard-coded colors: none of `Color.red/.blue/.orange`, `Color(red:)`, or literal `.tint(.color)` exist in iOS views. Outside views: `ReportExporter.swift:99,135` `.background(.white)`; `WaiverPDFRenderer.swift:68,89` `UIColor.gray`/`.black`. System semantic styles are widespread: `.secondary` ~35 sites, `.tertiary` ~8, `.quaternary` at `SetTableView.swift:173` and `ExerciseListView.swift:20`.

## Q4: How does the watch target source colors and icons, and what visual elements appear in watch views?

### Findings
- `project.yml:35-39`: TrainMeWatch sources are `Watch`, `Shared`, and `Sources/AppIcon.icon` as a resource. It does not compile `Sources/Assets.xcassets` or `Theme.swift`. There is no watch asset catalog and no accent color setting, so the watch uses the system default accent.
- `Shared/` holds only `Sync/*.swift` and `Timer/*.swift`; no SwiftUI, no colors, no images. No `Theme.` or `Color(` appears in `Watch/` or `Shared/`.
- `Watch/TrainMeWatchApp.swift:21-28`: `WindowGroup { TimerScreen().environment(model) }`; no background or tint.
- `Watch/TimerScreen.swift:22-38` (running): `Text("Rest"/"Timed set").font(.headline)`; `ProgressView(timerInterval:countsDown:)` with `.progressViewStyle(.circular)` and no tint (the only ring); center `Text(timerInterval:).font(.title3.monospacedDigit())`; `Button("+N s")` and `Button("Skip", role: .destructive)`, text-only. Idle state (`:40-42`) shows QuickStartView.
- `Watch/QuickStartView.swift:11-32`: `ScrollView`/`VStack(spacing: 8)`; up-next `Button(..., systemImage: "stopwatch")` `.borderedProminent` (`:14-17`); rest `Button("Rest N s", systemImage: "timer")` (`:31`), default pick `.borderedProminent`, others `.bordered` (`:20-24`).
- These two symbols are the only imagery on the watch. No explicit colors, gradients, custom backgrounds, Theme fonts, Gauge, or custom ring exist.

## Q5: What SF Symbols are used, with which rendering modes, weights, and colors, and are any reused with different meanings?

### Findings
- No `.symbolRenderingMode`, `.symbolVariant`, `.symbolEffect`, `.imageScale`, or `.contentTransition` exists in `Sources/`, `Watch/`, or `Shared/`. All symbols render in default monochrome mode. No `UIImage(systemName:)`. `ClientReportView.swift:128` `.symbol(.circle)` is a Charts marker, not an SF Symbol.
- Tab bar (`RootView.swift`): `calendar` (`:60`), `person.2.fill` (`:75`), `list.clipboard.fill` (`:87`), `dumbbell.fill` with `role: .search` (`:95`), `gearshape.fill` (`:100`). Four of five are `.fill`; `calendar` is not. No separate selected-state symbols.
- Each list's EmptyState reuses its tab symbol: `ScheduleView.swift:58` calendar, `ClientListView.swift:39` person.2.fill, `WorkoutListView.swift:38` list.clipboard.fill, `ExerciseListView.swift:31` dumbbell.fill.
- Symbol names are stored as parameters in `HeroScreen.swift:5`, `IconButton.swift:6`, `EmptyState.swift:6`, the `StatusChip.swift:18` tuple, and `MetricStepper.swift:26`. No enum of symbol raw values exists.
- Font/weight on symbols: `MetricStepper.swift:29` `.title3.weight(.bold)`; `SetTableView.swift:144` `.headline`; `StatusChip.swift:9` `.caption.weight(.semibold)`; `ScheduleView.swift:176`/`SessionRunView.swift:72` `.caption`; `SessionRunView.swift:56,61`, `ErrorBanner.swift:12`, `WaiverTemplateEditView.swift:22` `.callout`; `TimerBar.swift:31` `.subheadline.weight(.semibold)`; `HeroScreen.swift:27` `.system(size: 44)`. All others inherit.
- Same symbol, different meanings:
  - `checkmark.circle`: "Mark Completed" action (`SessionRunView.swift:116`), "No screening flags" state (`ClearanceBadge.swift:16`), resolved diff item (`AssessmentDetailView.swift:22`).
  - `checkmark.circle.fill`: Completed chip (`StatusChip.swift:21`) and the "Delete set N" IconButton with `role: .destructive` and success tint (`SetTableView.swift:100-101`).
  - `checkmark`: log a set (`SetTableView.swift:143`) and picker selection marker (`SessionEditView.swift:116`).
  - `xmark.circle(.fill)`: Cancelled (`SessionRunView.swift:119`, `StatusChip.swift:22`) and clear-value (`OptionalStepper.swift:21,74`).
  - `plus`: six add actions and the numeric increment (`MetricStepper.swift:22`).
  - `archivebox`: archived status (`ClientDetailView.swift:153`) and Archive action (`:169`).
  - `timer`: rest timer (`TimerBar.swift:30,58`, `Watch/QuickStartView.swift:31`) and timed-set countdown (`SetTableView.swift:160`).
  - `stopwatch`: timed set (`TimerBar.swift:30`) and up-next exercise (`QuickStartView.swift:14`).
  - `exclamationmark.triangle.fill`: client injuries (`SessionRunView.swift:59`) and data-store failure (`TrainMeApp.swift:117`).
  - `square.and.arrow.up`: send waiver (`ClientWaiverSection.swift:12`), share report (`ShareReportMenu.swift:13`), export data (`SettingsView.swift:87`).
  - `checkmark.seal`: clearance received (`ClearanceBadge.swift:13`) and "Mark signed" action (`ClientWaiverSection.swift:16`).
- Different symbols, same concept:
  - Alerts: `exclamationmark.octagon.fill` (danger, errors), `exclamationmark.triangle.fill` (warning), `exclamationmark.shield.fill` (`WaiverTemplateEditView.swift:20`), `exclamationmark.circle` (`AssessmentDetailView.swift:26`), `clock.badge.exclamationmark` (`ClientDetailView.swift:81`), `externaldrive.badge.exclamationmark` (`ScheduleView.swift:16`), `cross.case.fill` (`SessionRunView.swift:54`, `ClearanceBadge.swift:10`).
  - Session status: StatusChip uses `.fill` forms; the SessionRunView menu (`:116-122`) uses outline forms of the same symbols.
  - Navigation: `chevron.backward` (`IntakeFlowView.swift:39`) vs `chevron.left`/`chevron.right` (`ScheduleView.swift:119,123`).
  - Waiver states: `doc.text` (none, `ClientWaiverSection.swift:79`), `clock` (sent, `:82`), `checkmark.seal.fill` (signed, `:85`).
  - Empty-chart states: `chart.line.uptrend.xyaxis` (`ClientReportView.swift:16`), `chart.xyaxis.line` (`:116`), `chart.bar` (`:175`).
- Color on symbols: warning at 9 sites, success at 4, danger at 3, `.secondary` at 8, `.tertiary` at 2 (OptionalStepper). Everything else inherits the accent via `RootView.swift:113`.
- Overflow menus use `ellipsis.circle` consistently (`SessionRunView.swift:165`, `ClientDetailView.swift:174`) with `.labelStyle(.iconOnly)` and accessibility labels.

## Q6: How does the screenshot script produce the App Store and guide images, what drives it, and what references them?

### Findings
- `scripts/screenshots.sh` usage: `[--dark] [--only <name>]` (`:4-24`). Default appearance is light (`:15`); `--dark` sets `SUFFIX="-dark"` (`:24`). No `-dark` files currently exist in either output directory.
- Simulators: `PHONE` default "iPhone 18 Pro Max", `WATCH` default "Apple Watch Ultra 4 (49mm)" (`:13-14`), env-overridable; `udid()` resolves via `simctl list devices available` (`:35-37`).
- Build (`:39-45`): `xcodegen generate` then `xcodebuild -scheme TrainMe -configuration Debug ... -derivedDataPath build/ScreenshotsDerivedData CODE_SIGNING_ALLOWED=NO build`. Watch app is the embedded `Watch/TrainMeWatch.app` (`:44-45`). Debug is required because demo code is `#if DEBUG`.
- Phone flow (`:85-100`): `simctl ui appearance`, status bar override to 9:41 / full signal / 100% (`:88-89`), install, loop over `PHONE_SHOTS` (`:73-83`). Six store+guide shots (01-schedule-week … 06-workout-builder, all `scheduleMode=week`) and five guide-only shots (schedule-day, clients, workouts, exercises, settings). Each writes `docs/guide/images/<name><SUFFIX>.png` (`:95`) and store shots are copied to `docs/app-store/screenshots/` (`:98`).
- Launch args: phone `-demoData -hasSeenBackupNotice YES -lastExportAt <now-3600>` (`:70`) plus `-demoScreen <screen> -scheduleMode <mode>` (`:97`); watch `-demoData -demoWatch running|idle` (`:110`).
- `shot()` (`:54-67`): launch with `--terminate-running-process`, wait `FIRST_FRAME_WAIT=25`, `simctl io screenshot`, retry up to 3 times if below `MIN_PHONE_BYTES=150000` (`:30-33`). Watch minimum is 0.
- Watch flow (`:102-112`): `w1-timer-running` (running) and `w2-quick-start` (idle), bundle `com.madacgrav.trainme.watchkitapp`, written to app-store then copied to guide. No dark variant; watch appearance is not set.
- Size check (`:114-128`): phone must be 1320×2868 or 1290×2796; watch one of 422×514, 410×502, 416×496, 396×484, 368×448. Measured: `01-schedule-week.png` 1320×2868, `clients.png` 1320×2868, `w1-timer-running.png` 422×514.
- Demo data: `Sources/Support/DemoLaunch.swift:5-36` parses `-demoData`/`-demoScreen` (10 screens mapped to tab indices); `Sources/Support/DemoData.swift:17-33` builds an in-memory ModelContainer (12 exercises, named workouts, clients, sessions); `Sources/Support/DemoRoute.swift:5-30` roots deep screens without back buttons; `Watch/WatchDemo.swift:5-23` supplies the running rest timer or idle "Plank 45 s" up-next. `Tests/DemoDataTests.swift:7-47` asserts counts and arg parsing.
- References: `docs/app-store/metadata.md:129-151` lists all eight filenames with captions and says to regenerate with the script (`:151`); `docs/app-store/checklist.md:34,49`; guide pages `docs/guide/{index,scheduling,running-a-session,clients-and-intake,reports,health-assessments-waivers,workouts-and-exercises,settings,apple-watch}.md` embed the images with `{: width=...}`; `docs/index.md:6` embeds the icon PNG; `docs/changelog.md:60,66` mention the icon in text only; `README.md:74` describes the icon and asset paths.
- `scripts/check-docs-links.sh:2-24` validates that every `](target)` and `src="target"` in `docs/**/*.md` (excluding `docs/app-store/`) and `README.md` resolves to an existing file, so it covers the guide images and `images/icon.png`. `check-guide-labels.sh`, `check-metadata-lengths.sh`, and `sync-changelog.sh` do not touch images.

## Q7: What did the 2026-10-26 design records settle, and what verification did they use?

### Findings
- **review-gaps-and-app-icon/design.md**: Icon Composer `.icon` format, concept "dumbbell plus rising line" (`:3-4`). Deep teal→indigo gradient, white dumbbell, warm amber stroke; mono/tinted uses silhouette only; layers square, unmasked, full-bleed per HIG (`:104-106`). AccentColor is amber from the icon, set via `project.yml` (`:107-109`). Out of scope: alternate icons, iPad, Catalyst (`:152`). Risk: `icon.json` schema undocumented; mitigation is to start from an Icon Composer-saved file, keep ≤4 groups, validate with `actool`, keep an appiconset fallback (`:157-161`).
- **review-gaps-and-app-icon/plan.md**: original SVGs had stroke-width 56 and r=44 (`:109-113`); AccentColor was single-entry `#F59E0B` (`:123-134`). Verification (`:173-182`, all ticked): `actool` compile, pbxproj grep, build with zero AppIcon warnings, 57 tests, simulator home-screen check in light and dark. Fallback (`:165-171`) never needed.
- **ui-refresh-and-icon/design.md**: energetic, dark-first theme with full light support (`:3-5`). Findings at the time: one appearance only, 56px stroke flagged as thin by HIG, orange meaning three things (`:35-38`, `:19-20`). Desired icon: bolder geometry (stroke ≥96px, larger end cap), explicit dark and mono specializations, gradient aligned to brandPrimary/brandSecondary, AccentColor dark entry (`:66-68`). Theme decisions (`:108-115`): semantic tokens in one `Theme.swift` over colorsets; amber reserved for the one primary action per screen; teal for charts/brand, indigo for secondary series; gold for personalBest; report/PDF pages keep white background and forced light scheme (`:98-99`); no `.glassEffect` on content rows (`:103-104`). Icon edited as text with actool + simulator gate (`:124-126`). Out of scope: alternate icons and watchOS icon work (`:139`).
- **ui-refresh-and-icon/plan.md**: palette table (`:59-69`) matches the current colorsets exactly. Phase 5 (`:1006-1068`): export a reference from Icon Composer.app and copy its key names (`:1010-1016`); `line.svg` → stroke 104, r72; `dumbbell.svg` rewritten thicker; new `background-dark.svg` and `line-mono.svg`; `dumbbell-mono.svg` deemed unnecessary (`:1019-1033`). Automated gate: `xcrun actool --compile ... --platform iphonesimulator --minimum-deployment-target 26.0 --app-icon AppIcon ... Sources/AppIcon.icon Sources/Assets.xcassets | grep -ci error` must print 0; tests pass at 115 (`:1063-1064`). Manual gate: long-press home screen → Edit Home Screen → Light/Dark/Tinted/Clear, capture `p5-icon-*.png`, line visible at 60pt (`:1067`). Note at `:1123`: the mono layer is declared under Icon Composer's `tinted` appearance.
- Test command (`:14`): `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test`. Screenshot recipe (`:17-26`): build to `build/DerivedData`, `simctl install/launch booted`, capture light, dark, and AX3 (`content_size accessibility-extra-large`) per phase. Phase 6 check: `grep -rn "\.orange\b" Sources` returns 0 (`:1101-1108`). Merged as PR #36 (`:1134`).
- Captured evidence in `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/`: p1-schedule, p2-{clients,exercises,settings,workouts}, p2-lock-dark, p3-session, p4-about-you-light, p5-icon-{clear,dark,default,tinted}, p6-* light/dark/ax3 sets.
- **ui-refresh-and-icon/research.md:407** records that the committed `icon.json` group order (foreground first) differs from the plan's (background first). Confirmed in the current file.

## Cross-Cutting Observations
- Brand color appears in exactly three places: the icon SVGs, the nine colorsets, and the report charts. The teal/indigo brand pair is never used on a non-chart iOS surface; amber accent carries all interactive color via the TabView tint.
- The in-app palette is flat: no gradients, materials beyond `.bar`, shadows, or symbol rendering modes exist. Visual hierarchy comes from `.secondary`/`.tertiary` text, Surface vs SurfaceRaised, and low-opacity tinted capsules/rows (0.10–0.18).
- The watch is fully system-styled and shares nothing visual with the phone except the icon bundle.
- Every screen's empty state reuses its tab symbol inside `ContentUnavailableView` with system styling.
- Docs imagery is regenerated end to end by `scripts/screenshots.sh` from in-memory demo data; the only non-generated image is the 196px docs icon PNG.
- Prior work established `actool` compile plus simulator home-screen captures as the icon gate, and light/dark/AX3 simulator captures as the UI gate.

## Open Areas
- How `docs/images/icon.png` was produced is not recorded anywhere in the repo.
- The `clear` appearance has no explicit layer data; its exact rendering is only observable in `p5-icon-clear.png`, which was not inspected visually.
- `SessionRunView.swift:133` `.tint(Theme.Colors.success)` on the top ProgressView was noted but not traced in context.
- The watch icon rendering (circle mask) was not captured in any prior screenshot set; `supported-platforms.circles` exists but no watch home-screen capture is on disk.
