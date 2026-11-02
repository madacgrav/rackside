# Implementation Plan

## Overview
Give TrainMe a warm, energetic "electric sunset" identity in six places:
- a reinvented kettlebell app icon
- a new palette
- per-area colored badges on empty and hero screens and on rows
- a brand-gradient session progress bar
- a brand-tinted watch
- regenerated docs and App Store imagery

Light and dark mode both keep legible contrast.

## Conventions (read first)
- **Test command** (every phase): `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5`. It must end in `** TEST SUCCEEDED **`.
- **Build-only command**: the same command with `build` in place of `test`.
- **Capture recipe.**
  1. Build with `-derivedDataPath build/DerivedData`.
  2. Run `xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/TrainMe.app`.
  3. Run `xcrun simctl launch --terminate-running-process booted com.madacgrav.trainme -demoData -hasSeenBackupNotice YES -demoScreen <screen>`.
  4. Wait about 5 s.
  5. Run `xcrun simctl io booted screenshot <file>`.
  - **Appearance.** Use `xcrun simctl ui booted appearance light|dark`.
  - **AX3.** Use `xcrun simctl ui booted content_size accessibility-extra-large`, and reset afterwards with `content_size large`.
  - **Output folder.** Save captures to `thoughts/qrspi/2026-11-02-icon-and-imagery-refresh/screenshots/` as `p<N>-<screen>-{light,dark,ax3}.png`. Create the folder first.
- **Color roles.** Views reference `Theme.*` only, never `Color(red:)` and never named system colors such as `.orange`. New colors are colorsets.
- **Fixed badge fills.** White symbols sit only on the fixed (universal) `Fill*` colorsets. These are deep enough for white in both modes. Never put a white symbol on an adaptive brand or semantic color, because the dark values are light and white on them falls to about 1.6–2.8:1.

### Final palette (verified contrast, WCAG)

Adaptive colorsets have light and dark values:

| Colorset | Light | Dark | Notes |
|---|---|---|---|
| AccentColor | #D9480F | #F25C0C | white on fill 4.30 / 3.33; dark on raised 5.33 |
| BrandPrimary | #E11D48 | #FB7185 | charts series 1, watch ring (rose; Phase 1 fallback applied) |
| BrandSecondary | #C2185B | #F0509A | charts series 2 |
| BrandTertiary (new) | #6D28D9 | #A78BFA | info tint ("Not screened") |
| Success | #15803D | #4ADE80 | light on surface 4.71 |
| Warning | #B45309 | #FBBF24 | light on surface 4.71 |
| Danger | #DC2626 | #FB7185 | light on surface 4.53 |
| PersonalBest | #A16207 | #FFC21A | light on surface 4.62 |
| Surface | #FBF7F4 | #120B17 | |
| SurfaceRaised | #FFFFFF | #1E1426 | |

Universal colorsets are new, have one value, and are always under white symbols:

| Colorset | Value | White contrast |
|---|---|---|
| FillCoral | #E0391A | 4.40 |
| FillMagenta | #C2185B | 5.87 |
| FillViolet | #6D28D9 | 7.10 |
| FillTeal | #0F766E | 5.47 |
| FillGray | #636366 | 5.99 |

**Deviations from design.md, decided while planning:**
- The dark accent is `#F25C0C` instead of `#FF7A1A`, because white on `#FF7A1A` is only 2.61:1.
- Badge fills are fixed `Fill*` colorsets instead of the adaptive brand colors, which fail with white symbols in dark mode.
- The Exercises area is teal instead of orange, so it doesn't blur with the coral Schedule area and the orange accent. Teal is a cool counterpoint inside the sunset set.
- The icon needs no `kettlebell-mono.svg`, because the kettlebell is already white, the same reasoning the prior dumbbell work used.

Hex → sRGB component conversion is the value ÷ 255 to 3 decimals. For example `#D9480F` → red 0.851, green 0.282, blue 0.059.

---

## Phase 1: Sunset palette and Theme tokens

### Changes

#### 1. Recolor existing colorsets
**Files**: `Sources/Assets.xcassets/{AccentColor,BrandPrimary,BrandSecondary,Success,Warning,Danger,PersonalBest,Surface,SurfaceRaised}.colorset/Contents.json`
**Action**: modify. Replace the `components` in the universal entry (light) and the `luminosity: dark` entry with the values from the adaptive palette table. Keep the JSON shape exactly as it is (see `BrandPrimary.colorset/Contents.json`).

#### 2. New colorsets
**Files**:
- `Sources/Assets.xcassets/BrandTertiary.colorset/Contents.json`: adaptive, same two-entry shape.
- `Sources/Assets.xcassets/Fill{Coral,Magenta,Violet,Teal,Gray}.colorset/Contents.json`: universal only.

**Action**: create.

```json
{
  "colors": [
    { "color": { "color-space": "srgb",
        "components": { "alpha": "1.000", "red": "0.878", "green": "0.224", "blue": "0.102" } },
      "idiom": "universal" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

The snippet above is FillCoral (`#E0391A`). The other fills follow the same shape.

A Python one-liner can generate the component strings: `print(*(f"{int(h[i:i+2],16)/255:.3f}" for i in (0,2,4)))`.

#### 3. Theme tokens
**File**: `Sources/Support/Theme.swift`
**Action**: modify. Add to `Theme.Colors`, then add the new enums and the helper.

```swift
// in enum Colors
static let brandTertiary = Color("BrandTertiary")

/// Fixed (non-adaptive) fills that always sit under a white symbol or initials.
enum Fills {
    static let coral = Color("FillCoral")
    static let magenta = Color("FillMagenta")
    static let violet = Color("FillViolet")
    static let teal = Color("FillTeal")
    static let gray = Color("FillGray")
    static let all: [Color] = [coral, magenta, violet, teal]
}

enum Gradients {
    /// Sunset brand gradient; safe under white in both appearances.
    static let brand = LinearGradient(
        colors: [Fills.coral, Fills.magenta, Fills.violet],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// One color + symbol per app area, used by empty states and badges.
enum Area: CaseIterable {
    case schedule, clients, workouts, exercises, settings

    var color: Color {
        switch self {
        case .schedule: Fills.coral
        case .clients: Fills.magenta
        case .workouts: Fills.violet
        case .exercises: Fills.teal
        case .settings: Fills.gray
        }
    }

    /// Asset name behind `color`, for tests.
    var colorName: String {
        switch self {
        case .schedule: "FillCoral"
        case .clients: "FillMagenta"
        case .workouts: "FillViolet"
        case .exercises: "FillTeal"
        case .settings: "FillGray"
        }
    }

    /// Matches the tab symbols in RootView.
    var systemImage: String {
        switch self {
        case .schedule: "calendar"
        case .clients: "person.2.fill"
        case .workouts: "list.clipboard.fill"
        case .exercises: "dumbbell.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Stable palette pick for an identifier (FNV-1a; never `hashValue`, which is seeded per launch).
static func avatarIndex(for key: String) -> Int {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return Int(hash % UInt64(Fills.all.count))
}
static func avatarColor(for key: String) -> Color { Fills.all[avatarIndex(for: key)] }
```

The helper `avatarIndex(for:)` is used by Phase 4 and is tested here.

If Swift 6 strict concurrency flags `static let brand: LinearGradient` or `static let all: [Color]` as not concurrency-safe, make them computed properties instead: `static var brand: LinearGradient { … }`.

#### 4. Tests
**File**: `Tests/ThemeTests.swift`
**Action**: create. The file uses Swift Testing, like the other tests.

```swift
import SwiftUI
import Testing
import UIKit
@testable import TrainMe

private func named(_ name: String, _ style: UIUserInterfaceStyle) throws -> UIColor {
    let bundle = Bundle(identifier: "com.madacgrav.trainme") ?? .main
    let color = try #require(UIColor(named: name, in: bundle, compatibleWith: nil))
    return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
}

private func luminance(_ c: UIColor) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

@Test(arguments: ["Success", "Warning", "Danger", "PersonalBest"])
func textRolesAreReadableOnSurfaces(name: String) throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
        for surface in ["Surface", "SurfaceRaised"] {
            #expect(contrastRatio(try named(name, style), try named(surface, style)) >= 4.5,
                    "\(name) on \(surface) in \(style == .light ? "light" : "dark")")
        }
    }
}

@Test func accentIsReadableAsTintAndAsButtonFill() throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
        let accent = try named("AccentColor", style)
        #expect(contrastRatio(accent, try named("Surface", style)) >= 3)
        #expect(contrastRatio(.white, accent) >= 3)
    }
}

@Test(arguments: Theme.Area.allCases)
func areaFillsCarryWhiteSymbols(area: Theme.Area) throws {
    #expect(contrastRatio(.white, try named(area.colorName, .dark)) >= 4.4)
    #expect(!area.systemImage.isEmpty)
}

@Test func areaColorsAreDistinct() {
    #expect(Set(Theme.Area.allCases.map(\.colorName)).count == Theme.Area.allCases.count)
}

@Test func avatarIndexIsStableAndSpread() {
    let keys = (0..<50).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
    #expect(keys.map(Theme.avatarIndex) == keys.map(Theme.avatarIndex))
    #expect(Set(keys.map(Theme.avatarIndex)).count == Theme.Fills.all.count)
}
```

The tests run hosted in the app, so the app bundle resolves the colorsets. If `UIColor(named:in:)` returns nil, add `TEST_HOST` and `BUNDLE_LOADER` to the TrainMeTests settings in `project.yml`:

```yaml
TEST_HOST: $(BUILT_PRODUCTS_DIR)/TrainMe.app/TrainMe
BUNDLE_LOADER: $(TEST_HOST)
```

### Verification
#### Automated
- [x] The test command passes, including the 5 new `ThemeTests` tests.
- [x] `grep -rnE "Color\(red:|\.orange\b|Color\.(red|blue|green|yellow|purple|pink)\b" Sources/Features Sources/RootView.swift Sources/TrainMeApp.swift` prints nothing.
- [x] `xcrun actool --compile /tmp/p1-out --platform iphonesimulator --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist /tmp/p1-out/p.plist Sources/AppIcon.icon Sources/Assets.xcassets 2>&1 | grep -ci error` prints `0`. Run `mkdir -p /tmp/p1-out` first.

#### Manual
- [x] Capture `schedule`, `report`, and `session` in light and dark, as `p1-*`.
- [x] Orange appears only on the Add button, the selected tab, and buttons.
- [x] Report charts are coral and magenta, with gold PB points.
- [x] Dark surfaces are plum-black.
- [x] Warnings are amber.
- [x] If the coral chart line and the orange accent look alike on the report capture, change BrandPrimary to `#E11D48` / `#FB7185` and re-capture. *(Applied: coral bars were indistinguishable from the orange accent in both modes, so BrandPrimary is now rose `#E11D48` / `#FB7185`.)*

---

## Phase 2: Kettlebell app icon

### Changes

#### 1. Background gradients
**File**: `Sources/AppIcon.icon/Assets/background.svg`
**Action**: rewrite.

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF5A36"/>
      <stop offset="0.55" stop-color="#E8338C"/>
      <stop offset="1" stop-color="#7C3AED"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#g)"/>
</svg>
```

**File**: `Sources/AppIcon.icon/Assets/background-dark.svg`
**Action**: rewrite with the same structure. The stops are `#3B0A2A` at 0, `#4A0D3A` at 0.55, and `#1E0B4B` at 1.

#### 2. Kettlebell glyph
**File**: `Sources/AppIcon.icon/Assets/kettlebell.svg`
**Action**: create. It is a white silhouette with the handle drawn as a stroke, a round body, and a flat base, tilted −12°.

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <g transform="rotate(-12 512 540)" fill="#FFFFFF">
    <rect x="362" y="200" width="300" height="300" rx="140" fill="none" stroke="#FFFFFF" stroke-width="84"/>
    <circle cx="512" cy="600" r="250"/>
    <rect x="342" y="780" width="340" height="70" rx="35"/>
  </g>
</svg>
```

#### 3. Spark accent
**File**: `Sources/AppIcon.icon/Assets/spark.svg`
**Action**: create.

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <path fill="#FFFFFF" d="M820 150 L848 232 L930 260 L848 288 L820 370 L792 288 L710 260 L792 232 Z"/>
</svg>
```

#### 4. icon.json
**File**: `Sources/AppIcon.icon/icon.json`
**Action**: modify.
- Replace the foreground group's `layers` array with two layers, `kettlebell` and `spark`.
- Keep every other key byte-for-byte: `fill`, `fill-specializations`, the foreground group's `shadow`, `specular`, and `translucency`, the whole background group, and `supported-platforms`.

```json
"layers": [
  {
    "glass": true,
    "hidden": false,
    "image-name-specializations": [ { "value": "spark.svg" } ],
    "name": "spark",
    "position": { "scale": 1, "translation-in-points": [0, 0] }
  },
  {
    "glass": true,
    "hidden": false,
    "image-name-specializations": [ { "value": "kettlebell.svg" } ],
    "name": "kettlebell",
    "position": { "scale": 0.86, "translation-in-points": [0, 0] }
  }
]
```

The first layer in the array draws on top. This matches the existing order, where `dumbbell` was listed first.

#### 5. Remove old layers
**Files**: `Sources/AppIcon.icon/Assets/{dumbbell,line,line-mono}.svg`
**Action**: delete with `git rm`.

### Verification
#### Automated
- [x] `mkdir -p /tmp/p2-out && xcrun actool --compile /tmp/p2-out --platform iphonesimulator --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist /tmp/p2-out/p.plist Sources/AppIcon.icon Sources/Assets.xcassets 2>&1 | grep -ci error` prints `0`.
- [x] `grep -c "dumbbell.svg\|line.svg" Sources/AppIcon.icon/icon.json` prints `0`.
- [x] The test command passes.

#### Manual
- [x] Install, press Home, long-press, choose Edit, then Customize.
- [x] Capture `p2-icon-default.png`, `p2-icon-dark.png`, `p2-icon-tinted.png`, and `p2-icon-clear.png`.
- [x] The kettlebell (handle window, body, base) is clearly readable at home-screen size in all four.
- [x] The default is visibly brighter than the neighboring system icons, and the spark is visible.
- [x] (Not needed) Fallback if the glass renders muddy: set `"glass": false` on `kettlebell`, re-run actool, and re-capture.
- [x] (Not needed) Fallback if actool rejects the file twice: restore `icon.json` from git and swap only the SVG contents, reusing the old layer names and file names.

---

## Phase 3: Gradient hero and empty states

### Changes

#### 1. SymbolBadge component
**File**: `Sources/Features/Components/SymbolBadge.swift`
**Action**: create.

```swift
import SwiftUI

/// SF Symbol knocked out of a filled rounded square (Settings-style app badge).
struct SymbolBadge<Fill: ShapeStyle>: View {
    let systemImage: String
    let fill: Fill
    var size: CGFloat
    var symbol: Color = .white

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbol)
            }
            .accessibilityHidden(true)
    }
}
```

#### 2. EmptyState
**File**: `Sources/Features/Components/EmptyState.swift`
**Action**: modify.
- Replace `let systemImage: String` with `let area: Theme.Area`.
- Add `@ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 88`.
- Replace the label closure:

```swift
ContentUnavailableView {
    VStack(spacing: Theme.Spacing.md) {
        SymbolBadge(systemImage: area.systemImage, fill: area.color, size: badgeSize)
        Text(title).font(Theme.Fonts.display(.title2))
    }
    .accessibilityElement(children: .combine)
} description: { ...unchanged... } actions: { ...unchanged... }
```

**Call sites** to update:
- `Sources/Features/Schedule/ScheduleView.swift:58`: `EmptyState(title: "No sessions this day", area: .schedule)`
- `Sources/Features/Clients/ClientListView.swift:37-43`: `systemImage: "person.2.fill"` becomes `area: .clients`.
- `Sources/Features/Workouts/WorkoutListView.swift:38`: `EmptyState(title: "No workouts yet", area: .workouts)`
- `Sources/Features/Exercises/ExerciseListView.swift:31`: `EmptyState(title: "No exercises", area: .exercises)`

#### 3. HeroScreen
**File**: `Sources/Features/Components/HeroScreen.swift`
**Action**: modify.
- Replace `var tint: Color = .secondary` with `let fill: AnyShapeStyle` and `let symbol: Color`.
- The init becomes `init(systemImage:title:message:fill: some ShapeStyle = Theme.Gradients.brand, symbol: Color = .white, primary:extra:)`, storing `AnyShapeStyle(fill)`.
- Change `iconSize` from 44 to 96.
- Replace the `Image(systemName:)` block with:

```swift
SymbolBadge(systemImage: systemImage, fill: fill, size: iconSize, symbol: symbol)
```

**Call sites**:
- `Sources/Features/Lock/LockGateView.swift:46`: unchanged, so it gets the gradient by default.
- `Sources/TrainMeApp.swift:116-121`: `tint: Theme.Colors.warning` becomes `fill: Theme.Colors.warning, symbol: Theme.Colors.surface`. Warning is adaptive, so the symbol knocks out in the surface color: near-white on dark amber in light mode, plum-black on bright amber in dark mode.

### Verification
#### Automated
- [x] The test command passes.
- [x] `grep -rn "EmptyState(" Sources | grep -c systemImage` prints `0`.

#### Manual
- [x] Empty store: run `xcrun simctl uninstall booted com.madacgrav.trainme`, reinstall, and launch with `-hasSeenBackupNotice YES` and no `-demoData`.
- [x] Capture each tab's empty state *(Exercises is seeded on a fresh store, so its capture uses a no-match search query.)* as `p3-empty-{schedule,clients,workouts,exercises}-{light,dark,ax3}.png`.
- [x] Each badge uses its area color: coral, magenta, violet, and teal.
- [x] Nothing clips at AX3. *(Badge size is capped at 96pt so it stays readable in short overlays. Clients, Workouts and Exercises are fine. The Schedule overlay is only the strip under the calendar, and at AX3 the two-line title still runs under the tab bar, as a two-line title did before this change; the strip's height is a Schedule layout limit, out of scope here.)*
- [x] Enable the app lock in the simulator if the app offers it, relaunch, and capture `p3-lock-dark.png`. It should show the gradient badge. If the lock can't be enabled in the simulator, check the `HeroScreen` `#Preview` in Xcode instead.
- [x] VoiceOver (Accessibility Inspector) reads the empty-state title once and doesn't announce the symbol. *(Verified by construction: the badge is `accessibilityHidden` and the badge+title VStack is one combined element. Not run in Accessibility Inspector.)*

---

## Phase 4: Row badges, client avatars, and colorful status symbols

### Changes

#### 1. IconBadge and ClientAvatar
**File**: `Sources/Features/Components/IconBadge.swift`
**Action**: create.

```swift
import SwiftUI

/// 28pt Settings-style row icon.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        SymbolBadge(systemImage: systemImage, fill: color, size: size)
    }
}
```

**File**: `Sources/Features/Components/ClientAvatar.swift`
**Action**: create.

```swift
import SwiftUI

/// Initials on a stable per-client color.
struct ClientAvatar: View {
    let name: String
    let id: UUID
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Theme.avatarColor(for: id.uuidString))
            .frame(width: size, height: size)
            .overlay {
                Text(Self.initials(name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
```

#### 2. Settings rows
**File**: `Sources/Features/Settings/SettingsView.swift`
**Action**: modify.
- Wrap row labels as `Label { Text(...) } icon: { IconBadge(systemImage:color:) }`.
- The Units segmented picker stays as is.

| Row | Symbol | Fill |
|---|---|---|
| Liability waiver template (NavigationLink) | `doc.text.fill` | `Theme.Fills.magenta` |
| Default rest (Picker label) | `timer` | `Theme.Fills.violet` |
| Export all data… | `square.and.arrow.up` | `Theme.Fills.teal` |
| Import from file… | `square.and.arrow.down` | `Theme.Fills.teal` |
| Last export (LabeledContent label) | `clock.fill` | `Theme.Fills.gray` |
| Notifications (PermissionRow) | `bell.fill` | `Theme.Fills.coral` |
| Calendar (PermissionRow) | `calendar` | `Theme.Fills.coral` |
| Version | `info.circle.fill` | `Theme.Fills.gray` |
| User guide | `book.fill` | `Theme.Fills.violet` |
| What's new | `sparkles` | `Theme.Fills.magenta` |
| Privacy policy | `hand.raised.fill` | `Theme.Fills.teal` |
| Support | `questionmark.bubble.fill` | `Theme.Fills.coral` |
| License (GPL v3) | `doc.plaintext.fill` | `Theme.Fills.gray` |

Example patterns:

```swift
NavigationLink { WaiverTemplateEditView(repo: waivers) } label: {
    Label { Text("Liability waiver template") } icon: { IconBadge(systemImage: "doc.text.fill", color: Theme.Fills.magenta) }
}
Picker(selection: $defaultRestSeconds) { ...unchanged... } label: {
    Label { Text("Default rest") } icon: { IconBadge(systemImage: "timer", color: Theme.Fills.violet) }
}
Button { ...unchanged export task... } label: {
    Label { Text("Export all data…") } icon: { IconBadge(systemImage: "square.and.arrow.up", color: Theme.Fills.teal) }
}
LabeledContent { Text(lastExportText) } label: {
    Label { Text("Last export") } icon: { IconBadge(systemImage: "clock.fill", color: Theme.Fills.gray) }
}
Link(destination: AppLinks.guide) {
    Label { Text("User guide") } icon: { IconBadge(systemImage: "book.fill", color: Theme.Fills.violet) }
}
```

`PermissionRow` gains `let systemImage: String` and `let color: Color`. Its `LabeledContent(title, value: status)` becomes:

```swift
LabeledContent { Text(status) } label: {
    Label { Text(title) } icon: { IconBadge(systemImage: systemImage, color: color) }
}
```

Update the two call sites to pass the values from the table.

#### 3. Client detail action rows
**File**: `Sources/Features/Clients/ClientDetailView.swift`
**Action**: modify. Three rows change:
- `Button("New screening", systemImage: "plus")` becomes `Button { … } label: { Label { Text("New screening") } icon: { IconBadge(systemImage: "stethoscope", color: Theme.Fills.coral) } }`.
- `Button("New assessment", systemImage: "plus")` becomes the same pattern with `figure.strengthtraining.traditional` and `Theme.Fills.violet`.
- `NavigationLink("View progress") { … }` becomes `NavigationLink { … } label: { Label { Text("View progress") } icon: { IconBadge(systemImage: "chart.line.uptrend.xyaxis", color: Theme.Fills.teal) } }`.

**File**: `Sources/Features/Waiver/ClientWaiverSection.swift`
**Action**: modify.
- `Button("Send waiver…", systemImage: "square.and.arrow.up")` becomes a label with `IconBadge(systemImage: "doc.text.fill", color: Theme.Fills.magenta)`.
- Add `.symbolRenderingMode(.hierarchical)` to the three `statusRow` labels and the error label. Their colors are unchanged.

#### 4. Client list avatars
**File**: `Sources/Features/Clients/ClientListView.swift`
**Action**: modify the row label at `:28`.

```swift
HStack(spacing: Theme.Spacing.md) {
    ClientAvatar(name: client.name, id: client.id)
    TitleCaptionRow(title: client.name, caption: client.goal)
}
```

#### 5. Status symbols
- **`Sources/Features/Health/ClearanceBadge.swift`**: add `.symbolRenderingMode(.hierarchical)` to all four labels.
  - `.received` changes from `.secondary` to `Theme.Colors.success`.
  - `.clear` changes from `.secondary` to `Theme.Colors.success`.
  - `.notScreened` changes from `.secondary` to `Theme.Colors.brandTertiary`.
- **`Sources/Features/Components/StatusChip.swift`**: add `.symbolRenderingMode(.hierarchical)` after the `Label`.
- **`Sources/Features/Components/ErrorBanner.swift`**: add `.symbolRenderingMode(.hierarchical)` after the `Label`.

#### 6. Tests
**File**: `Tests/ThemeTests.swift`
**Action**: append.

```swift
@Test func avatarInitials() {
    #expect(ClientAvatar.initials("Priya Shah") == "PS")
    #expect(ClientAvatar.initials("Jordan") == "J")
    #expect(ClientAvatar.initials("Mary Ann  Lee") == "ML")
    #expect(ClientAvatar.initials("") == "?")
}
```

### Verification
#### Automated
- [x] The test command passes.
- [x] `grep -n "foregroundStyle(.secondary)" Sources/Features/Health/ClearanceBadge.swift` prints nothing.

#### Manual
- [x] Capture `settings`, `clients`, and `client` in light, dark, and AX3, as `p4-*`.
- [x] Badges align with the row text.
- [x] Avatars show initials in varied colors.
- [x] Nothing truncates badly at AX3.
- [x] (By construction: `IconBadge` wraps `SymbolBadge`, which is `accessibilityHidden`; not run in Accessibility Inspector.) Accessibility Inspector reads "User guide" and "Liability waiver template" without symbol names.
- [x] Client rows read the name and goal only. *(By construction: `ClientAvatar` is `accessibilityHidden`.)*
- [x] Clearance: "No screening flags" is green on the featured demo client. Confirm on the `client` capture.

---

## Phase 5: Session and timer accents

### Changes

#### 1. GradientProgressBar
**File**: `Sources/Features/Components/GradientProgressBar.swift`
**Action**: create.

```swift
import SwiftUI

/// Capsule progress bar filled with the brand gradient.
struct GradientProgressBar: View {
    private enum Source { case value(Double), countdown(ClosedRange<Date>) }
    private let source: Source
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 6

    init(value: Double, total: Double = 1) {
        source = .value(total > 0 ? value / total : 0)
    }

    /// Remaining fraction of a countdown, like `ProgressView(timerInterval:countsDown: true)`.
    init(countdown interval: ClosedRange<Date>) { source = .countdown(interval) }

    static func remainingFraction(of interval: ClosedRange<Date>, at now: Date) -> Double {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return 0 }
        return min(max(interval.upperBound.timeIntervalSince(now) / total, 0), 1)
    }

    var body: some View {
        switch source {
        case .value(let fraction):
            bar(fraction)
        case .countdown(let interval):
            TimelineView(.animation(minimumInterval: 0.2)) { context in
                bar(Self.remainingFraction(of: interval, at: context.date))
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.Gradients.brand)
                    .frame(width: max(clamped > 0 ? height : 0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}
```

#### 2. TimerBar
**File**: `Sources/Features/Timer/TimerBar.swift`
**Action**: modify. Replace the `ProgressView(timerInterval:…) { … } currentValueLabel: { … } .tint(Theme.Colors.accent)` block (`:47-53`) with:

```swift
GradientProgressBar(countdown: timer.startedAt...timer.endAt)
    .accessibilityHidden(true) // the combined label above already speaks the countdown
```

#### 3. SessionRunView top progress
**File**: `Sources/Features/Session/SessionRunView.swift`
**Action**: modify `:132-133`. Replace `ProgressView(value: viewModel.progress).tint(Theme.Colors.success)` with `GradientProgressBar(value: viewModel.progress)`. Keep `.padding(.horizontal)` and both existing accessibility modifiers.

#### 4. Tests
**File**: `Tests/GradientProgressBarTests.swift`
**Action**: create.

```swift
import Foundation
import Testing
@testable import TrainMe

@Test func remainingFractionCountsDown() {
    let start = Date(timeIntervalSince1970: 0)
    let interval = start...start.addingTimeInterval(100)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start) == 1)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start.addingTimeInterval(25)) == 0.75)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start.addingTimeInterval(200)) == 0)
    #expect(GradientProgressBar.remainingFraction(of: start...start, at: start) == 0)
}
```

### Verification
#### Automated
- [x] The test command passes. `TimerMathTests`, `TimerStoreTests`, and `SessionRunViewModelTests` are unchanged.
- [x] `grep -n "ProgressView" Sources/Features/Timer/TimerBar.swift` prints nothing.

#### Manual
- [x] Launch `-demoScreen session`. The top bar shows the gradient at partial progress.
- [x] Log a set to start the rest timer. *(The session demo route already starts a rest timer; captured at 1:28 and again at 1:21 to confirm the bar shrinks.)* The bottom bar shows the gradient shrinking smoothly.
- [x] Capture `p5-session-{light,dark,ax3}.png` with the timer running.
- [x] (By construction: the existing `accessibilityLabel`/`accessibilityValue` modifiers are kept on the new bar; not run with VoiceOver.) VoiceOver on the top bar reads "Session progress, 2 of N sets".

---

## Phase 6: Watch light touch

### Changes

#### 1. Share the color catalog
**File**: `project.yml`
**Action**: modify the TrainMeWatch target.

```yaml
    sources:
      - Watch
      - Shared
      - path: Sources/AppIcon.icon
        buildPhase: resources
      - path: Sources/Assets.xcassets
        buildPhase: resources
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        # ...existing keys unchanged
```

#### 2. WatchTheme
**File**: `Watch/WatchTheme.swift`
**Action**: create.

```swift
import SwiftUI

/// Watch-side names for the shared phone palette (Sources/Assets.xcassets).
enum WatchTheme {
    static let ring = Color("BrandPrimary")
    static let upNext = Color("FillViolet")
}
```

`FillViolet` is used rather than BrandTertiary because the watch is always dark and the button carries white text.

#### 3. TimerScreen ring
**File**: `Watch/TimerScreen.swift`
**Action**: modify. Add `.tint(WatchTheme.ring)` after `.progressViewStyle(.circular)`.

#### 4. Quick-start up-next
**File**: `Watch/QuickStartView.swift`
**Action**: modify. Add `.tint(WatchTheme.upNext)` after the up-next button's `.buttonStyle(.borderedProminent)`. Rest buttons keep inheriting AccentColor.

### Verification
#### Automated
- [x] `xcodegen generate && xcodebuild -scheme TrainMeWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error|warning: .*(asset|actool|AccentColor)" | head` prints nothing.
- [x] The test command passes.
- [x] Run `scripts/screenshots.sh --only w1-timer-running`, then `scripts/screenshots.sh --only w2-quick-start`. Each run prints "All screenshots OK."

#### Manual
- [x] Open `docs/app-store/screenshots/w1-timer-running.png`. The ring is coral. *(Rose, since BrandPrimary took the Phase 1 fallback.)*
- [x] Open `w2-quick-start.png`. The up-next button is violet and the rest buttons are orange.
- [x] (Not captured: `simctl`'s HOME press only returns the watch simulator to its face, and the app grid needs the Simulator app driven on screen. Verified by geometry instead: every kettlebell point lies within 0.73 of the circle radius; the spark's farthest tips reach 0.95 of the radius, so nothing is trimmed by the circle.) On the watch simulator, press the crown to reach the home screen and capture `p6-watch-icon.png` with `xcrun simctl io <watch-udid> screenshot`. The kettlebell is centered and not clipped by the circle.
- [x] (Not needed) Fallback if the shared catalog makes actool fail for watchOS: create `Watch/Assets.xcassets/` with copies of `AccentColor`, `BrandPrimary`, and `FillViolet` only, point the `project.yml` entry at it, and rebuild.

---

## Phase 7: Docs, store imagery, and changelog

### Changes

#### 1. Docs icon
**File**: `docs/images/icon.png`
**Action**: regenerate.

```bash
rm -rf /tmp/p7-icon && mkdir -p /tmp/p7-icon
xcrun actool --compile /tmp/p7-icon --platform iphonesimulator --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist /tmp/p7-icon/p.plist Sources/AppIcon.icon Sources/Assets.xcassets
ls /tmp/p7-icon/*.png
sips -z 196 196 /tmp/p7-icon/AppIcon60x60@3x.png --out docs/images/icon.png
```

- `ls` shows which PNGs actool wrote. Use the largest iPhone one, normally `AppIcon60x60@3x.png` at 180px.
- If actool writes no PNGs (only `Assets.car`), crop the icon from `p2-icon-default.png` instead. Find the icon's bounds by eye, then run `sips -c <h> <w> --cropOffset <y> <x>` followed by `sips -z 196 196`.

#### 2. Screenshots
**Action**: run `scripts/screenshots.sh` in the morning, so the demo times look natural. It regenerates `docs/guide/images/*.png` and `docs/app-store/screenshots/*.png`. Don't edit the script.

#### 3. Changelog
**File**: `CHANGELOG.md`
**Action**: modify. Under `## [Unreleased] — 1.0.0`, add to `### Changed`:

```markdown
- A brand-new app icon: a bold kettlebell on a coral-to-violet sunset gradient, with dark, tinted and clear variants on iPhone and Apple Watch.
- A brighter, warmer look throughout: colored badges on empty screens, settings and client rows, client initials avatars, and a gradient progress bar during sessions and rest timers.
- The Apple Watch timer ring and quick-start buttons now use TrainMe's colors.
```

Then run `scripts/sync-changelog.sh`.

### Verification
#### Automated
- [x] `scripts/screenshots.sh` ends with "All screenshots OK."
- [x] `scripts/check-docs-links.sh` passes.
- [x] `sips -g pixelWidth -g pixelHeight docs/images/icon.png` reports 196 × 196.
- [x] `git diff --stat docs/changelog.md` shows the new lines.
- [x] The test command passes, as a final full run.

#### Manual
- [x] Review the six iPhone store shots against the captions in `docs/app-store/metadata.md:137-149`. Each shot still shows what its caption claims.
- [x] Open `docs/index.md` in a Markdown preview and check that the new icon shows. *(Checked the regenerated `docs/images/icon.png` directly; actool's largest PNG is 152px, upscaled to 196px, displayed at 96px.)*
- [x] Skim `docs/guide/images/settings.png` and `clients.png`. Badges and avatars are visible.
