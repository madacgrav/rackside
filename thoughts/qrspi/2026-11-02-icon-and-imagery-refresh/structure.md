# Structure Outline

## Approach
Land the "electric sunset" palette and Theme tokens first, so every later slice only consumes roles. Then ship one visible surface per phase:
- the kettlebell icon
- hero and empty states
- rows and status
- session accents
- the watch
- regenerated docs imagery

Each phase builds, passes tests, and is checked with light, dark, and AX3 simulator captures.

**Commands used in every phase**
- **Test:** `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5`
- **Captures:** follow the prior recipe (`2026-10-26-ui-refresh-and-icon/plan.md:17-26`). Launch with `-demoData -demoScreen <screen>` and save to `thoughts/qrspi/2026-11-02-icon-and-imagery-refresh/screenshots/p<N>-<screen>-{light,dark,ax3}.png`.

---

## Phase 1: Sunset palette and Theme tokens
Recolor the whole app via colorsets and add the gradient and area tokens. This is visible immediately in four places:
- the tab tint
- the plum dark surfaces
- the charts, which become coral and magenta
- amber warnings

**Files**
- `Sources/Assets.xcassets/*.colorset/Contents.json`: nine colorsets get new values.
- `Sources/Assets.xcassets/BrandTertiary.colorset/Contents.json`: new.
- `Sources/Support/Theme.swift`.
- `Tests/ThemeTests.swift`: new.

**Key changes**
- `Theme.Colors.brandTertiary: Color`: new.
- `Theme.Gradients.brand: LinearGradient`: coral → magenta → violet, top-leading → bottom-trailing.
- `enum Theme.Area: CaseIterable { case schedule, clients, workouts, exercises, settings }`
  - `var color: Color`
  - `var systemImage: String`, matching the tab symbols at `RootView.swift:60-100`.
- A test helper `contrastRatio(_ a: UIColor, _ b: UIColor) -> Double`. It resolves each named color with `UITraitCollection(userInterfaceStyle: .light/.dark)`.

**Verify**
- Tests pass.
- `ThemeTests` asserts the text-role colors meet ≥4.5:1 on Surface and SurfaceRaised in both styles. The text roles are Success, Warning, Danger, and Accent (accent at ≥3:1).
- `ThemeTests` asserts white meets ≥3:1 on every Area color and on AccentColor.
- `ThemeTests` asserts each `Theme.Area` has a distinct color and a non-empty symbol.
- `grep -rn "Color(red:\|\.orange\b" Sources/Features` prints nothing.
- Manually capture schedule, report, and session in light and dark. Confirm the following:
  - orange shows only on actions
  - charts are coral and magenta
  - warnings are amber
  - dark surfaces are plum-black
  - coral and orange are distinguishable

---

## Phase 2: Kettlebell app icon
Replace the dumbbell and rising-line icon with the tilted white glass kettlebell on the sunset gradient. Include the dark and tinted variants. Both targets pick it up.

**Files**
- `Sources/AppIcon.icon/icon.json`
- `Sources/AppIcon.icon/Assets/background.svg` and `background-dark.svg`: rewritten.
- `Sources/AppIcon.icon/Assets/kettlebell.svg`, `kettlebell-mono.svg`, and `spark.svg`: new.
- `dumbbell.svg`, `line.svg`, and `line-mono.svg`: deleted.

**Key changes**
- `icon.json` foreground group holds two layers:
  - `kettlebell`, with `glass: true`, rotation in the SVG, and a tinted specialization of `kettlebell-mono.svg`.
  - `spark`, with `glass: true` and `hidden` under tinted, or omitted if unsupported.
- `icon.json` background group gets a dark specialization of `background-dark.svg`.
- `fill-specializations` stays unchanged (`icon.json:3-8`).

**Verify**
- `xcrun actool --compile /tmp/icon-out --platform iphonesimulator --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist /tmp/icon-out/p.plist Sources/AppIcon.icon Sources/Assets.xcassets 2>&1 | grep -ci error` prints 0.
- Tests pass.
- Manually: install, go to the Home Screen, and choose Edit → Light, Dark, Tinted, Clear. Capture `p2-icon-{default,dark,tinted,clear}.png`.
- The kettlebell must read clearly at 60pt and stand out next to the system apps.
- Fallback if glass looks muddy: set `glass: false` on the kettlebell with flat white.

---

## Phase 3: Gradient hero and empty states
Turn blank screens into branded moments. The symbol renders white inside a colored or gradient rounded-square badge.

**Files**
- `Sources/Features/Components/SymbolBadge.swift`: new.
- `EmptyState.swift`
- `HeroScreen.swift`
- Call sites:
  - `ScheduleView.swift:58`
  - `ClientListView.swift:37`
  - `WorkoutListView.swift:38`
  - `ExerciseListView.swift:31`
  - `LockGateView.swift:46`
  - `TrainMeApp.swift:116`

**Key changes**
- `struct SymbolBadge: View { init(systemImage: String, fill: some ShapeStyle, size: CGFloat) }`
  - A rounded square that is about 0.27× its size.
  - The symbol is white and hierarchical.
  - It is `accessibilityHidden`.
- `EmptyState`:
  - Adds `init(title:, area: Theme.Area, description:, action:)`. The symbol and fill both come from the area.
  - The existing `systemImage:` initializer stays for the report empty states.
  - Uses a custom `label:` with a `SymbolBadge` of about 88pt (`@ScaledMetric`) above the title.
- `HeroScreen`: `tint: Color` becomes `fill: AnyShapeStyle = AnyShapeStyle(Theme.Gradients.brand)`, rendered with `SymbolBadge`.
  - The lock screen uses the gradient.
  - The recovery screen uses `Theme.Colors.warning`.

**Verify**
- Tests pass.
- Manually: launch with an empty store, so there is no `-demoData`. Capture these empty states in light, dark, and AX3:
  - Schedule day
  - Clients
  - Workouts
  - Exercises
- Capture the lock screen with lock enabled.
- Each badge must use its area color and must not clip at AX3.

---

## Phase 4: Row badges, client avatars, and colorful status symbols
Add Settings-style colored icon badges and client initials avatars, and switch status symbols to hierarchical rendering with semantic color, so lists stop reading gray.

**Files**
- `Sources/Features/Components/IconBadge.swift`: new.
- `Sources/Features/Components/ClientAvatar.swift`: new.
- `SettingsView.swift`
- `ClientDetailView.swift`
- `ClientListView.swift`
- `ClearanceBadge.swift`
- `ClientWaiverSection.swift`
- `StatusChip.swift`
- `ErrorBanner.swift`
- `Tests/ThemeTests.swift`: extended.

**Key changes**
- `struct IconBadge: View { init(systemImage: String, color: Color) }`
  - It is 28pt (`@ScaledMetric`) with a filled 7pt-radius square and a white symbol.
  - It is used as a `Label` icon via `LabeledContent` or the `Label { } icon: { }` form.
- `struct ClientAvatar: View { init(name: String, id: PersistentIdentifier) }`
  - Shows initials on a filled circle.
- `static func Theme.avatarColor(for key: String) -> Color` gives a deterministic, stable palette pick using a stable hash, not `hashValue`.
- ClearanceBadge's "OK" states change from `.secondary` to `Theme.Colors.success`. Status symbols gain `.symbolRenderingMode(.hierarchical)`.

**Verify**
- Tests pass.
- `ThemeTests` asserts `avatarColor(for:)` is stable across calls and covers at least 4 distinct colors over sample names.
- Manually capture Settings, Clients, and Client detail in light, dark, and AX3. Confirm three things:
  - badges align with row text
  - VoiceOver reads row titles only, not badge symbols
  - no warning or success meaning changed

---

## Phase 5: Session and timer accents
Make the live session the most energetic screen by filling the progress bars with the brand gradient.

**Files**
- `Sources/Features/Components/GradientProgressBar.swift`: new.
- `Sources/Features/Timer/TimerBar.swift`
- `Sources/Features/Session/SessionRunView.swift`

**Key changes**
- `struct GradientProgressBar: View { init(value: Double, total: Double = 1) }`
  - A capsule track drawn as `.quaternary` and filled with `Theme.Gradients.brand`.
  - Carries an accessibility value as a percentage.
- `TimerBar.swift:53` ProgressView is replaced by `GradientProgressBar` driven by the existing timeline value.
- `SessionRunView.swift:133` top progress becomes `GradientProgressBar`.
- The logged-set (success) and focused-cell (accent) tints are unchanged.

**Verify**
- Tests pass, including `TimerMathTests` and `SessionRunViewModelTests`, which must stay unchanged.
- Manually capture the session screen with the timer running, using `-demoScreen session` and then starting a rest, in light, dark, and AX3.
- The bar must animate smoothly and VoiceOver must announce progress.

---

## Phase 6: Watch light touch
The watch shares the phone's colors. It gets the orange accent, a coral timer ring, and tinted quick-start buttons. It also gets a check of the new icon inside the watch circle.

**Files**
- `project.yml` (TrainMeWatch, `:35-42`)
- `Watch/WatchTheme.swift`: new.
- `Watch/TimerScreen.swift`
- `Watch/QuickStartView.swift`

**Key changes**
- In `project.yml`, add `- path: Sources/Assets.xcassets` with `buildPhase: resources`, and add `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`.
- `enum WatchTheme { static let ring = Color("BrandPrimary"); static let upNext = Color("BrandTertiary") }`
- `TimerScreen`: the circular ProgressView gets `.tint(WatchTheme.ring)`.
- `QuickStartView`: the up-next button gets `.tint(WatchTheme.upNext)`. Rest buttons inherit the accent.

**Verify**
- Tests pass.
- `xcodebuild -scheme TrainMe ... build` succeeds for the embedded watch app with no actool warnings.
- Run `scripts/screenshots.sh --only w1-timer-running` and `--only w2-quick-start`. Confirm the ring is coral and the buttons are colored.
- On the watch simulator home screen, capture `p6-watch-icon.png` showing the kettlebell centered in the circle.
- Fallback: create `Watch/Assets.xcassets` with only AccentColor, BrandPrimary, and BrandTertiary.

---

## Phase 7: Docs, store imagery, and changelog
Regenerate every published image so the docs and App Store match the new look.

**Files**
- `docs/images/icon.png`
- `docs/app-store/screenshots/*.png`
- `docs/guide/images/*.png`
- `CHANGELOG.md`, then `scripts/sync-changelog.sh` to update `docs/changelog.md`

**Key changes**
- Generated output only, with no Swift changes.
- `icon.png` is a 196px export of the new default icon, cropped from the Phase 2 home-screen capture or composited from the SVGs.

**Verify**
- `scripts/screenshots.sh` prints "All screenshots OK." Run it in the morning.
- `scripts/check-docs-links.sh` passes.
- `sips -g pixelWidth docs/images/icon.png` reports 196.
- Manually review the six store shots against the captions in `docs/app-store/metadata.md:137-149`.

---

## Testing Checkpoints

| After | What should be true |
|---|---|
| P1 | New palette live everywhere. `ThemeTests` contrast and area checks green. No raw colors in Features. |
| P2 | Kettlebell icon compiles with actool and shows distinct Default, Dark, Tinted, and Clear on the home screen. |
| P3 | All 4 empty states and 2 hero screens show colored or gradient badges, with no AX3 clipping. |
| P4 | Settings, Clients, and Client detail rows have badges or avatars. Status symbols are hierarchical and colored. |
| P5 | Session and timer progress use the brand gradient bar. Timer tests unchanged and green. |
| P6 | Watch builds with the shared catalog. Ring is coral, buttons are tinted, and the watch icon is verified. |
| P7 | Docs and store screenshots regenerated. Docs icon refreshed. Link check and size check pass. |

Phases 2 and 6 touch no shared Swift with Phases 3-5, so they can run in parallel after Phase 1. Phase 7 must run last.
