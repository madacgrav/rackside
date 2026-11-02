# Design Discussion

Owner answers (2026-11-02):
- Icon: reinvention, not a tweak. Concept is a bold kettlebell on a vivid gradient.
- Palette: new vivid palette, "electric sunset" mood (coral, magenta, violet, orange, gold).
- Imagery: all four areas: per-area colored symbols, gradient hero/empty states, colored row icon badges, session and timer accents.
- Watch: light touch with brand accent, tinted timer ring, colored quick-start buttons.

## Current State
- **Icon.** `Sources/AppIcon.icon/icon.json` has a foreground group with glass `dumbbell` and `rising line` layers (`:10-65`) and a background group with a gradient layer (`:66-100`).
  - `background.svg` is `#0F766E → #3730A3`. `dumbbell.svg` is white rects. `line.svg` is an amber 104px stroke.
  - Dark swaps the background (`:72-80`). Tinted swaps the line to `line-mono.svg` (`:41-44`). Clear is system-derived.
  - Rendered, it reads as a dark, muted tile (`thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/p5-icon-default.png`).
  - Both targets use the same bundle (`project.yml:17`, `:35-39`). The watch renders it in a circle (`icon.json:102-107`).
- **Palette.** Nine colorsets in `Sources/Assets.xcassets/` with light and dark values. They are exposed as `Theme.Colors.*` via `Color("Name")` (`Sources/Support/Theme.swift:6-14`).
  - There are no gradients anywhere in `Sources/`.
  - Brand teal and indigo appear only in report charts (`F/Reports/ClientReportView.swift:129,184`).
  - Amber accent appears only on the tab tint (`Sources/RootView.swift:113`) and a few toggles.
- **Imagery.** About 60 SF Symbols, all default monochrome. There is no `.symbolRenderingMode` anywhere.
  - Empty states reuse tab symbols inside system-styled `ContentUnavailableView` (`F/Components/EmptyState.swift:10-20`).
  - `HeroScreen` shows a 44pt gray or warning symbol (`F/Components/HeroScreen.swift:26-29`).
  - List rows are plain text on SurfaceRaised. There are no leading icons.
  - Screens read as grayscale (`docs/guide/images/workouts.png`, `docs/app-store/screenshots/01-schedule-week.png`).
- **Session and timer.** `TimerBar` is a `.bar` material with an accent ProgressView (`F/Timer/TimerBar.swift:16,53`). SessionRunView's top progress is success-tinted (`F/Session/SessionRunView.swift:133`).
- **Watch.** Fully system-styled. It compiles neither the asset catalog nor Theme.swift (`project.yml:35-39`).
  - It has one untinted circular ring (`Watch/TimerScreen.swift:22-38`).
  - It uses only two symbols, `stopwatch` and `timer` (`Watch/QuickStartView.swift:14,31`).
- **Docs imagery.** `scripts/screenshots.sh` regenerates the eleven guide images and eight store images from demo data (`:73-112`). The 196px `docs/images/icon.png` (`docs/index.md:6`) has no recorded source.

## Desired End State
A trainer opens TrainMe and it feels warm, energetic, and unmistakably fitness.
- **Icon.** The home-screen icon is a chunky, slightly tilted white glass kettlebell on a hot coral → magenta → violet gradient.
  - It stands out next to Fitness and Messages.
  - It renders distinctly in Default, Dark, Tinted, and Clear, and inside the watch circle.
- **Palette.** In-app color uses a new sunset palette. Each area of the app has its own color, carried consistently through:
  - empty states
  - hero screens
  - row badges
  - session accents
- **Accent.** Orange stays reserved for actions.
- **Watch.** The watch picks up the accent and brand ring, so it visibly belongs to the phone app.

**Verification**
- `xcrun actool` compile of `Sources/AppIcon.icon` plus `Sources/Assets.xcassets` reports 0 errors. Recipe: prior `plan.md:1063-1064`.
- The full test suite passes after `xcodegen generate`.
- Home-screen captures exist in all four icon appearances, plus a watch home-screen capture.
- Light, dark, and AX3 simulator captures exist for Schedule, Clients, Client detail, Session, Workouts, Exercises, Settings, an empty state, and the lock screen.
- Text contrast in light mode is at least 4.5:1 for every color used on body text, and at least 3:1 for icon-only and large-text uses. These are checked from the hex values in the plan.
- `grep` finds no raw `Color(red:` or named system colors such as `.orange` in `Sources/` views. PDF and export renderers are exempt.
- `scripts/screenshots.sh` is re-run, `scripts/check-docs-links.sh` passes, and `docs/images/icon.png` shows the new icon.

## Patterns to Follow
- **Color tokens.** Colors are colorsets with a universal plus `luminosity: dark` entry (any colorset `Contents.json:3-32`), exposed only through `Theme` (`Theme.swift:3-14`). New tokens (gradient, area colors, tertiary brand) live in Theme.swift. Views keep "roles, never raw colors" (`Theme.swift:3`).
- **Screen helpers.** `themedScreen()` and `themedRows()` (`Theme.swift:40-47`) remain the way screens get surfaces. Don't hand-roll backgrounds.
- **Components.** Shared imagery components take the symbol name as a parameter (`EmptyState.swift:6`, `HeroScreen.swift:5`, `IconButton.swift:6`). New badge styling goes into these components, so the 4 EmptyState and 2 HeroScreen call sites pick it up with a small added color or area argument.
- **Status capsules.** Low-opacity tinted capsules are an existing idiom to keep: `StatusChip.swift:12-25` at 0.18 opacity, `SetTableView.swift:105` at 0.10.
- **Icon authoring.** Edit `icon.json` and the SVGs as text (prior design, `2026-10-26-ui-refresh-and-icon/design.md:124-126`).
  - Reuse the existing key names: `image-name-specializations` with `appearance: dark|tinted`, `fill-specializations`, group `shadow/specular/translucency` (`icon.json:3-8,33-45,56-64`).
  - Keep 1024 viewBox square full-bleed layers.
- **Watch resources.** The watch already shares a resource from `Sources/` via an explicit `buildPhase: resources` entry (`project.yml:35-39`). Share the color catalog the same way rather than duplicating colorsets.
- **Reports and PDF.** Pages keep a white background and forced light scheme (prior design `:98-99`, `Sources/Services/ReportExporter.swift:99,135`). Charts pick up new brand colors through the existing tokens only.

**Do NOT follow:**
- One warm hue meaning several things. The prior refresh fixed "orange meant three things" (prior design `:19-20`). The sunset palette has several warm hues, so each must keep one role.
- Symbol-meaning collisions such as `checkmark.circle.fill` on a destructive "Delete set" button (`SetTableView.swift:100-101`). Don't copy these into new badges.
- Glass on content rows, which prior design `:103-104` rejected. Glass stays on the icon only.

## Design Decisions
1. **Icon concept: bold kettlebell.**
   - Layers:
     - Background is a diagonal 3-stop gradient, coral `#FF5A36` → magenta `#E8338C` → violet `#7C3AED`.
     - Foreground is one white glass kettlebell (body and handle as one silhouette), rotated about −12°, scaled about 0.8.
     - An optional small white "spark" glass layer at the upper right gives specular pop.
   - The dumbbell and rising-line layers and their SVGs are removed.
   - **Why:** One chunky silhouette reads at 29pt and inside the watch circle. It is name-agnostic, so the app name review doesn't block it.
2. **Icon variants.**
   - Default uses the bright gradient.
   - Dark uses a deep plum → indigo gradient (about `#3B0A2A → #1E0B4B`) with the same white kettlebell.
   - Tinted uses a white kettlebell (`kettlebell-mono.svg` if the glass layer needs a flat variant) with no spark.
   - Clear stays system-derived.
   - **Why:** This mirrors today's dark and tinted mechanics (`icon.json:3-8,41-44`) with no new schema keys.
3. **Palette "electric sunset" with fixed roles.** Hex values are starting points. The plan confirms contrast.

   | Token | Role | Light | Dark |
   |---|---|---|---|
   | AccentColor | actions only: tab selection, primary buttons, Add | #D9480F | #FF7A1A |
   | BrandPrimary (coral) | Schedule area, gradient start, chart series 1 | #E0391A | #FF6A4D |
   | BrandSecondary (magenta) | Clients area, gradient mid, chart series 2 | #C2185B | #F0509A |
   | BrandTertiary (violet, new) | Workouts area, gradient end | #6D28D9 | #A78BFA |
   | Success | completed, logged | #15803D | #4ADE80 |
   | Warning (amber) | cautions | #B45309 | #FBBF24 |
   | Danger | errors, destructive | #DC2626 | #FB7185 |
   | PersonalBest (gold) | chart PB only | #A16207 | #FFC21A |
   | Surface | screen background | #FBF7F4 | #120B17 |
   | SurfaceRaised | rows | #FFFFFF | #1E1426 |

   - Warning moves from orange to amber so it no longer competes with the orange accent and coral brand.
   - Dark surfaces move from teal-black to plum-black to match the icon.
4. **Gradient and area tokens.** Theme.swift adds:
   - `Theme.Gradients.brand`, coral → magenta → violet.
   - `Theme.Area`, an enum with five cases: `schedule` (coral, `calendar`), `clients` (magenta, `person.2.fill`), `workouts` (violet, `list.clipboard.fill`), `exercises` (accent orange, `dumbbell.fill`), and `settings` (gray, `gearshape.fill`). Each case supplies a color and a symbol.
   - Empty states, row badges, and section imagery read their color and symbol from `Theme.Area`, so each area's color stays consistent.
   - **Why:** One mapping keeps "per-area color" consistent and testable.
5. **Tab bar stays single-tint.**
   - The iOS 26 `TabView` draws unselected items monochrome and the selected item in the tint (`RootView.swift:59-113`). Per-tab colors aren't supported without custom chrome.
   - Per-area color therefore appears on screen content, not in the tab bar. The tab tint remains AccentColor.
6. **Gradient hero and empty states.** `EmptyState` and `HeroScreen` render their symbol white, inside a rounded-square badge filled with the area color or the brand gradient (about 88pt, `@ScaledMetric`).
   - EmptyState keeps the `ContentUnavailableView` title, description, and action.
   - HeroScreen's warning and lock uses keep a semantic fill: warning for the store failure, brand gradient for lock.
7. **Row icon badges.** There is a new `IconBadge(systemImage:color:)` component: a 28pt rounded square with a filled color and a white symbol, sized like Settings.app. It goes on:
   - SettingsView rows
   - ClientDetailView action and section rows: screening, assessment, waiver, intake, report
   - ClientListView rows, as a colored initials avatar whose color is picked deterministically from the palette by client ID
   - WorkoutList and ExerciseList rows stay text-only to avoid noise.
8. **Symbol rendering.**
   - Status and alert symbols in `ClearanceBadge`, `ClientWaiverSection`, `StatusChip`, and `ErrorBanner` adopt `.symbolRenderingMode(.hierarchical)` with their existing semantic color.
   - Gray `.secondary` "OK" states (`ClearanceBadge.swift:14-20`) become success or brand-tinted, so screens aren't mostly gray.
9. **Session and timer accents.**
   - SessionRunView's top progress and `TimerBar`'s progress become a capsule filled with `Theme.Gradients.brand`.
   - The logged-set row keeps the success tint (`SetTableView.swift:105`).
   - The focused metric cell keeps the accent tint (`SetTableView.swift:131`).
10. **Watch light touch.**
    - Add `{path: Sources/Assets.xcassets, buildPhase: resources}` to TrainMeWatch and set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` on the watch target.
    - A tiny watch-local `WatchTheme` reads `Color("BrandPrimary")` and related names. Shared/ stays SwiftUI-free.
    - The timer ring gets `.tint(brandPrimary)`. The up-next button is tinted violet, rest buttons get the accent, and Skip stays destructive.
11. **Docs and store imagery.**
    - Re-run `scripts/screenshots.sh` (light, as today) after the UI lands.
    - Regenerate `docs/images/icon.png` at 196px from the new icon. Capture it from a simulator home-screen crop if no SVG compositing tool is available.
    - Add a changelog entry.
    - Metadata captions are unchanged.

## What We're NOT Doing
- No app rename. The separate name review stays separate, and the icon carries no lettering.
- No alternate app icons, widgets, complications, or iPad or Catalyst work.
- No per-item tab bar colors and no custom tab bar.
- No Liquid Glass or `.glassEffect` on content rows.
- No custom symbol animations (`.symbolEffect`) or new motion.
- No changes to report or PDF page backgrounds or the waiver PDF renderer colors.
- No general cleanup of the symbol-meaning collisions found in research. Only symbols placed inside new badges are chosen fresh.
- No dark-mode App Store screenshot set. Light screenshots are regenerated only.
- No watch layout changes beyond tint and color.

## Open Risks
- **Warm hues may blur.** Accent orange and coral BrandPrimary are close. The plan should check them side by side on the Schedule capture and nudge coral toward red or magenta if they blur.
- **Light-mode contrast.** Coral, magenta, and orange are weak as body text on white. The plan must keep them to fills, icons, and large text, and confirm white-on-fill contrast for badges and `.borderedProminent` buttons.
- **Warning vs personal best.** Amber Warning and gold PersonalBest are both yellow-family. They rarely co-occur (only `ClientReportView.swift:39`), but they need a visual check on the report screen.
- **Icon authoring.** Hand-authored glass silhouettes can render muddy. The `icon.json` schema is undocumented (prior design `:146-148`). Gate with actool and home-screen captures. Fall back to a flat white kettlebell if glass reads poorly.
- **Watch catalog sharing.** Sharing `Sources/Assets.xcassets` with the watch target is untested, and actool may complain about platform idioms. The fallback is a minimal `Watch/Assets.xcassets` with AccentColor and BrandPrimary only.
- **Screenshot timing.** `scripts/screenshots.sh` should run in the morning for natural times (`:6-7`) and takes several minutes per run.
- **Contrast arithmetic.** The hex values above are design intent. Final values may shift a few points once the plan checks contrast numerically.
