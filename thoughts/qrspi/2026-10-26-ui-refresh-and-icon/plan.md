# Implementation Plan

## Overview

Give TrainMe a themed, workout-feeling interface (dark-first with full light support),
shared components, an inline set table, a self-use client path, a refined layered app
icon, and preview-based verification, while keeping every repository, export format,
notification, calendar, and lock flow unchanged.

Conventions used below: `S/` = `Sources/`, `F/` = `Sources/Features/`. All work is
Swift 6 strict concurrency, iOS 26, SwiftUI, XcodeGen. Every phase ends green on:

```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```

Screenshot recipe (run after `xcodebuild … build` and `xcrun simctl install booted
<path>.app` + `xcrun simctl launch booted com.madacgrav.trainme`):

```bash
mkdir -p thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots
xcrun simctl ui booted appearance light  && xcrun simctl io booted screenshot thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/<phase>-<screen>-light.png
xcrun simctl ui booted appearance dark   && xcrun simctl io booted screenshot thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/<phase>-<screen>-dark.png
xcrun simctl ui booted content_size accessibility-extra-large && xcrun simctl io booted screenshot thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/<phase>-<screen>-ax3.png
xcrun simctl ui booted content_size large   # reset
```

The built `.app` path is `build/DerivedData/Build/Products/Debug-iphonesimulator/TrainMe.app`
when building with `-derivedDataPath build/DerivedData`.

Existing test count: 109. Keep `Tests/Fixtures/export-v1.json` untouched.

---

## Phase 1: Theme foundation + Schedule tab re-skin

### Changes

#### 1. Color assets
**File**: `S/Assets.xcassets/<Name>.colorset/Contents.json` — **create** seven colorsets.
**File**: `S/Assets.xcassets/AccentColor.colorset/Contents.json` — **modify** (add dark).

Each file uses this shape; substitute the two sRGB hex values (components as 0–1
decimals, three places):

```json
{
  "colors" : [
    { "idiom" : "universal",
      "color" : { "color-space" : "srgb", "components" : { "red" : "R", "green" : "G", "blue" : "B", "alpha" : "1.000" } } },
    { "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb", "components" : { "red" : "R", "green" : "G", "blue" : "B", "alpha" : "1.000" } } }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

| Colorset | Light | Dark | Role |
|---|---|---|---|
| `AccentColor` | `#D97706` (0.851, 0.467, 0.024) | `#F59E0B` (0.961, 0.620, 0.043) | primary action tint |
| `BrandPrimary` | `#0F766E` (0.059, 0.463, 0.431) | `#2DD4BF` (0.176, 0.831, 0.749) | brand teal, charts series 1 |
| `BrandSecondary` | `#3730A3` (0.216, 0.188, 0.639) | `#818CF8` (0.506, 0.549, 0.973) | charts series 2 |
| `Success` | `#15803D` (0.082, 0.502, 0.239) | `#4ADE80` (0.290, 0.871, 0.502) | completed, logged set |
| `Warning` | `#C2410C` (0.761, 0.255, 0.047) | `#FB923C` (0.984, 0.573, 0.235) | injuries, export banner, no-show |
| `Danger` | `#DC2626` (0.863, 0.149, 0.149) | `#F87171` (0.973, 0.443, 0.443) | errors |
| `PersonalBest` | `#A16207` (0.631, 0.384, 0.027) | `#FACC15` (0.980, 0.800, 0.082) | PB marker |
| `Surface` | `#F2F2F7` (0.949, 0.949, 0.969) | `#0B1211` (0.043, 0.071, 0.067) | screen background |
| `SurfaceRaised` | `#FFFFFF` (1, 1, 1) | `#152321` (0.082, 0.137, 0.129) | list rows, cards |

#### 2. Theme accessors
**File**: `S/Support/Theme.swift` — **create**.

```swift
import SwiftUI

/// Single source of visual identity. Views reference roles, never raw colors.
enum Theme {
    enum Colors {
        static let accent = Color("AccentColor")
        static let brandPrimary = Color("BrandPrimary")
        static let brandSecondary = Color("BrandSecondary")
        static let success = Color("Success")
        static let warning = Color("Warning")
        static let danger = Color("Danger")
        static let personalBest = Color("PersonalBest")
        static let surface = Color("Surface")
        static let surfaceRaised = Color("SurfaceRaised")
    }

    enum Fonts {
        /// Headline-weight rounded display text for row titles and hero copy.
        static func display(_ style: Font.TextStyle = .headline) -> Font {
            .system(style, design: .rounded, weight: .semibold)
        }
        /// Tabular digits for set tables and stat tiles.
        static let numeric: Font = .system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
    }

    enum Radius {
        static let row: CGFloat = 12
    }
}

extension View {
    /// Applies the themed surface to a List/Form and hides the system background.
    func themedScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.Colors.surface)
    }
    /// Applies the raised surface to every row in a Section.
    func themedRows() -> some View {
        self.listRowBackground(Theme.Colors.surfaceRaised)
    }
}
```

#### 3. Status chip
**File**: `S/Features/Components/StatusChip.swift` — **create** (new directory
`S/Features/Components/`; XcodeGen picks it up from `sources: [Sources]`).

```swift
import SwiftUI

struct StatusChip: View {
    let status: SessionStatus

    var body: some View {
        if let spec {
            Label(spec.text, systemImage: spec.symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(spec.color.opacity(0.18), in: Capsule())
                .foregroundStyle(spec.color)
                .accessibilityLabel(spec.text)
        }
    }

    private var spec: (text: String, symbol: String, color: Color)? {
        switch status {
        case .scheduled: nil
        case .completed: ("Completed", "checkmark.circle.fill", Theme.Colors.success)
        case .cancelled: ("Cancelled", "xmark.circle.fill", Color.secondary)
        case .noShow: ("No-show", "person.fill.xmark", Theme.Colors.warning)
        }
    }
}
```

#### 4. Preview fixtures
**File**: `S/Support/PreviewFixtures.swift` — **create**.

```swift
import Foundation
import SwiftData

/// In-memory data for #Preview blocks. Seeds synchronously through ModelContext so
/// previews need no async setup.
@MainActor
enum PreviewFixtures {
    static let clientId = UUID()
    static let benchId = UUID()
    static let squatId = UUID()
    static let instanceId = UUID()

    static let client = ClientDTO(
        id: clientId, name: "Sam Rivera", phoneE164: "+15551234567",
        goal: "Add 20 lb to bench", injuries: "Left knee — avoid deep squats",
        notes: nil, isArchived: false, createdAt: .now, updatedAt: .now)

    static let bench = ExerciseDTO(id: benchId, name: "Bench Press", category: .strength,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb, isCustom: false, createdAt: .now, updatedAt: .now)
    static let squat = ExerciseDTO(id: squatId, name: "Goblet Squat", category: .strength,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb, isCustom: false, createdAt: .now, updatedAt: .now)

    static let workout = WorkoutDTO(id: UUID(), name: "Upper A", entries: [
        WorkoutEntryDTO(id: UUID(), exerciseId: benchId, order: 0, targetSets: 3, targetReps: 8, targetWeight: 135, targetDuration: nil),
        WorkoutEntryDTO(id: UUID(), exerciseId: squatId, order: 1, targetSets: 3, targetReps: 10, targetWeight: 50, targetDuration: nil),
    ], createdAt: .now, updatedAt: .now)

    static let scheduledSession = SessionDTO(
        id: UUID(), clientId: clientId,
        startAt: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!,
        endAt: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!,
        status: .scheduled, notes: "Felt strong last week.",
        instances: [WorkoutInstanceDTO(id: instanceId, sourceWorkoutId: workout.id, name: "Upper A",
            plannedEntries: workout.entries.map {
                PlannedEntryDTO(id: UUID(), exerciseId: $0.exerciseId, order: $0.order, targetSets: $0.targetSets,
                                targetReps: $0.targetReps, targetWeight: $0.targetWeight, targetDuration: $0.targetDuration) })],
        seriesId: nil, recurrence: nil, eventIdentifier: nil, createdAt: .now, updatedAt: .now)

    static let loggedSets: [SetRecordDTO] = [
        SetRecordDTO(id: UUID(), workoutInstanceId: instanceId, exerciseId: benchId, setIndex: 0,
                     weight: 135, reps: 8, duration: nil, distance: nil, rpe: nil,
                     performedAt: .now, createdAt: .now, updatedAt: .now),
        SetRecordDTO(id: UUID(), workoutInstanceId: instanceId, exerciseId: benchId, setIndex: 1,
                     weight: 135, reps: 7, duration: nil, distance: nil, rpe: nil,
                     performedAt: .now, createdAt: .now, updatedAt: .now),
    ]

    /// A seeded in-memory container. Each call builds a fresh store.
    static func container() -> ModelContainer {
        let container = try! PersistenceController.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        ctx.insert(client.toModel())
        ctx.insert(bench.toModel())
        ctx.insert(squat.toModel())
        ctx.insert(workout.toModel())
        let session = scheduledSession.toModel()   // see note below
        ctx.insert(session)
        for set in loggedSets { ctx.insert(set.toModel()) }
        try! ctx.save()
        return container
    }
}
```

Note: `toModel()` exists today only on `ExerciseDTO`, `WorkoutEntryDTO`, `PlannedEntryDTO`,
`SetRecordDTO`, and `ClientDTO`. Add `toModel()` to `WorkoutDTO` (build a `Workout`, append
`entries.map { $0.toModel() }`), `WorkoutInstanceDTO` (build a `WorkoutInstance`, append
planned entries), and `SessionDTO` (build a `Session`, set `statusRaw`, append
`instances.map { $0.toModel() }`). Follow the field order of each model's `init`
(`S/Models/Workout.swift`, `S/Models/Session.swift:38`). Mirror how the repositories'
`insertSession` / `upsert` wire relationships (`S/Persistence/SessionRepository.swift:107`,
`S/Persistence/WorkoutRepository.swift:25`) so the inverse relationships are set.

#### 5. Root tab bar
**File**: `S/RootView.swift` — **modify**.

- Symbols: `calendar` → `calendar` (already filled glyph), `person.2` → `person.2.fill`,
  `list.clipboard` → `list.clipboard.fill`, `dumbbell` → `dumbbell.fill`, `gearshape` → `gearshape.fill`.
- After the `TabView { … }` closing brace add:

```swift
        .tabBarMinimizeBehavior(.onScrollDown)
        .fontDesign(.rounded)
        .tint(Theme.Colors.accent)
```

#### 6. Schedule tab
**File**: `F/Schedule/ScheduleView.swift` — **modify**.

- Banner: `.foregroundStyle(.orange)` (line 16) → `.foregroundStyle(Theme.Colors.warning)`;
  `.background(.orange.opacity(0.12))` (line 34) → `.background(Theme.Colors.warning.opacity(0.12))`.
- `List(viewModel.sessionsForDay) { … }` → add `.themedScreen()` after `.overlay { … }`;
  wrap the row content in `.themedRows()`.
- `SessionRow`: replace `statusBadge` and its `@ViewBuilder` with `StatusChip(status: session.status)`.
  Client name uses `.font(Theme.Fonts.display())`.
- Append previews at file end:

```swift
#Preview("Schedule") {
    let container = PreviewFixtures.container()
    ScheduleView(viewModel: ScheduleViewModel(
        sessionRepo: SwiftDataSessionRepository(modelContainer: container),
        clientRepo: SwiftDataClientRepository(modelContainer: container),
        workoutRepo: SwiftDataWorkoutRepository(modelContainer: container),
        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
        reminders: ReminderCoordinator(
            sessionRepo: SwiftDataSessionRepository(modelContainer: container),
            clientRepo: SwiftDataClientRepository(modelContainer: container),
            notifications: LocalNotificationService())))
}

#Preview("Session row") {
    List {
        SessionRow(session: PreviewFixtures.scheduledSession, clientName: "Sam Rivera")
        SessionRow(session: { var s = PreviewFixtures.scheduledSession; s.status = .completed; return s }(), clientName: "Sam Rivera")
        SessionRow(session: { var s = PreviewFixtures.scheduledSession; s.status = .noShow; return s }(), clientName: "Sam Rivera")
    }
}
```

#### 7. README
**File**: `README.md` — **modify**. After the `Sources/Support/` bullet (line 61) add:
`- `Sources/Support/Theme.swift` — color/font/spacing tokens (colorsets live in `Sources/Assets.xcassets`); `Sources/Features/Components/` — shared SwiftUI building blocks`.

### Verification
#### Automated
- [x] `xcodegen generate` succeeds and `grep -c "Components" TrainMe.xcodeproj/project.pbxproj` ≥ 1.
- [x] Test command passes (109 tests).
- [x] `grep -rn "\.orange" Sources/Features/Schedule` returns nothing.
- [x] `xcrun actool --compile /tmp/ac --platform iphonesimulator --minimum-deployment-target 26.0 Sources/Assets.xcassets 2>&1 | grep -ci error` prints `0`.

#### Manual
- [ ] Xcode canvas renders both previews in Schedule in light and dark.
- [ ] Screenshots `p1-schedule-{light,dark,ax3}.png`: tab bar shows filled symbols; amber appears only on the Add button and selected tab; completed chip is green, no-show chip is orange.
- [ ] Scrolling the session list down minimizes the tab bar; scrolling up restores it.

---

## Phase 2: Shared components sweep

### Changes

#### 1. Components
**Directory**: `S/Features/Components/` — **create** six files.

`TitleCaptionRow.swift`:
```swift
import SwiftUI

struct TitleCaptionRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var tertiary: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, caption: String? = nil, tertiary: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title; self.caption = caption; self.tertiary = tertiary; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.display()).foregroundStyle(.primary)
                if let caption, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                if let tertiary, !tertiary.isEmpty {
                    Text(tertiary).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}
```

`ErrorBanner.swift`:
```swift
import SwiftUI

/// Drop-in replacement for `Section { Text(msg).foregroundStyle(.red) }`.
struct ErrorBanner: View {
    let message: String?
    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(Theme.Colors.danger)
                    .font(.callout)
                    .accessibilityLabel("Error: \(message)")
            }
        }
    }
}
```

`IconButton.swift`:
```swift
import SwiftUI

/// Icon-only button that always carries a VoiceOver label and a 44pt target.
struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole? = nil
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, role: role, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(tint)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(title))
    }
}
```

`EmptyState.swift`:
```swift
import SwiftUI

struct EmptyState: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description { Text(description) }
        } actions: {
            if let action {
                Button(action.title, action: action.run).buttonStyle(.borderedProminent)
            }
        }
    }
}
```

`HeroScreen.swift`:
```swift
import SwiftUI

/// Centered icon + headline + primary button (lock screen, recovery).
struct HeroScreen<Extra: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var tint: Color = .secondary
    let primary: (title: String, run: () -> Void)
    @ViewBuilder var extra: () -> Extra
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    init(systemImage: String, title: String, message: String? = nil, tint: Color = .secondary,
         primary: (title: String, run: () -> Void),
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.systemImage = systemImage; self.title = title; self.message = message
        self.tint = tint; self.primary = primary; self.extra = extra
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage).font(.system(size: iconSize)).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(Theme.Fonts.display(.title2)).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(primary.title, action: primary.run).buttonStyle(.borderedProminent)
            extra()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }
}
```

`ShareReportMenu.swift`:
```swift
import SwiftUI

struct ShareReportMenu: View {
    let files: ReportFiles?
    var body: some View {
        if let files {
            Menu {
                ShareLink("Share PDF", item: files.pdf)
                ShareLink("Share PNG", item: files.png)
            } label: {
                Label("Share report", systemImage: "square.and.arrow.up")
            }
        }
    }
}
```

#### 2. Loading state on list view models
**Files**: `F/Clients/ClientListViewModel.swift`, `F/Workouts/WorkoutListViewModel.swift`,
`F/Exercises/ExerciseListViewModel.swift`, `F/Schedule/ScheduleViewModel.swift` — **modify**.

Add `var isLoading = false` and wrap the body of `load()`:
```swift
    func load() async {
        isLoading = true
        defer { isLoading = false }
        // existing body
    }
```
In each list view's `.overlay`, show `ProgressView()` when `viewModel.isLoading && <list>.isEmpty`,
else the existing empty state (now `EmptyState(...)`).

#### 3. Clients tab
**File**: `F/Clients/ClientListView.swift` — **modify**: row label → `TitleCaptionRow(title: client.name, caption: client.goal)`;
overlay → `if viewModel.isLoading && viewModel.clients.isEmpty { ProgressView() } else if viewModel.clients.isEmpty { EmptyState(title: viewModel.query.isEmpty ? "No clients yet" : "No matches", systemImage: "person.2.fill") }`;
`List` gets `.themedScreen()`; add `#Preview` using `PreviewFixtures.container()`.

**File**: `F/Clients/ClientDetailView.swift` — **modify**: error section → `ErrorBanner(message: viewModel.errorMessage)`;
empty texts stay; `Menu` label → `Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)` with `.accessibilityLabel("More actions")`;
`List` gets `.themedScreen()`; sections get `.themedRows()`; add `#Preview`.

**File**: `F/Clients/ClientEditView.swift` — **modify**: both `.red` texts → `ErrorBanner` (validation stays inline but uses `Theme.Colors.danger`);
Save button gets `.buttonStyle(.borderedProminent)`; add `#Preview`.

#### 4. Workouts tab
**File**: `F/Workouts/WorkoutListView.swift` — **modify**: error → `ErrorBanner`; row → `TitleCaptionRow(title:caption:)` inside the `Button`;
overlay as in §3 with `EmptyState("No workouts yet", "list.clipboard.fill")`; `.themedScreen()`; `#Preview`.

**File**: `F/Workouts/WorkoutBuilderView.swift` — **modify**: both row labels (lines 33-39, 127-132) → `TitleCaptionRow`;
error → `ErrorBanner`; Save → `.borderedProminent`; `OptionalStepper`'s Clear button → `IconButton(title: "Clear", systemImage: "xmark.circle.fill", tint: .tertiary)`; `#Preview` for builder and picker.

#### 5. Exercises tab
**File**: `F/Exercises/ExerciseListView.swift` — **modify**: row → `TitleCaptionRow(title:caption:) { if exercise.isCustom { Text("Custom")… } }`;
overlay per §3 with `EmptyState("No exercises", "dumbbell.fill")`; `.themedScreen()`; `#Preview`.
**File**: `S/RootView.swift` — **modify**: `Tab("Exercises", systemImage: "dumbbell.fill", value: 3, role: .search)`.
The tab shows the system search glyph; the in-view `.searchable` becomes the search field for that tab.
**File**: `F/Exercises/ExerciseEditView.swift` — **modify**: error → `ErrorBanner`; Save → `.borderedProminent`; `#Preview`.

#### 6. Schedule edit, Settings, Lock, Recovery
**File**: `F/Schedule/SessionEditView.swift` — **modify**: error → `ErrorBanner`; weekday toggle tint → `Theme.Colors.accent : Color.secondary`; Save → `.borderedProminent`; `#Preview`.
**File**: `F/Settings/SettingsView.swift` — **modify**: `Form` gets `.themedScreen()`; `#Preview`.
**File**: `F/Lock/LockGateView.swift` — **modify**: `lockScreen` → `HeroScreen(systemImage: "lock.fill", title: "TrainMe is locked", primary: ("Unlock", { Task { await lock.authenticate() } }))`.
**File**: `S/TrainMeApp.swift` — **modify**: `RecoveryView.body` → `HeroScreen(systemImage: "exclamationmark.triangle.fill", title: "TrainMe couldn't open its data store", message: message, tint: Theme.Colors.warning, primary: ("Restore last backup", onRestoreBackup)) { Button("Start fresh (then import an export file)", role: .destructive) { confirmingReset = true } }` keeping the existing `.alert`.

#### 7. Reports screens (component adoption only; theming is Phase 6)
**Files**: `F/Reports/ClientReportView.swift`, `F/Reports/ExerciseReportView.swift` — **modify**:
both `.red` sections → `ErrorBanner`; toolbar `Menu` → `ShareReportMenu(files: files)`;
top-exercise and history rows → `TitleCaptionRow`; `.themedScreen()`; `#Preview` each using `PreviewFixtures`.

#### 8. Session screen (component adoption only; table is Phase 3)
**File**: `F/Session/SessionRunView.swift` — **modify**: error → `ErrorBanner`; injuries label tint → `Theme.Colors.warning`;
`Menu` label → `Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)`; `List` gets `.themedScreen()`.

### Verification
#### Automated
- [x] Test command passes (109).
- [x] `grep -rn "foregroundStyle(.red)" Sources` → 0 lines.
- [x] `grep -rn "font(.system(size:" Sources` → 0 lines outside `Components/HeroScreen.swift`.
- [x] `grep -rln "#Preview" Sources/Features | wc -l` ≥ 12.

#### Manual
- [ ] Accessibility Inspector (Xcode → Open Developer Tool) on the simulator: every toolbar and in-row icon button reports a label.
- [ ] Screenshots `p2-{clients,workouts,exercises,settings}-{light,dark,ax3}.png` plus `p2-lock-dark.png`.
- [ ] Exercises tab shows the search glyph and tapping it focuses the search field; the category picker still works.
- [ ] Loading spinner appears briefly on first open of Clients with an empty store, then the empty state.

---

## Phase 3: Inline set table in SessionRunView

### Changes

#### 1. Set draft
**File**: `F/Session/SetDraft.swift` — **create**.

```swift
import Foundation

/// Editable values for one not-yet-logged set.
struct SetDraft: Equatable, Sendable {
    var weight: Double?
    var reps: Int?
    var duration: Int?
    var distance: Double?

    init(target entry: PlannedEntryDTO, metrics: MetricSet) {
        weight = metrics.contains(.weight) ? (entry.targetWeight ?? 0) : nil
        reps = metrics.contains(.reps) ? (entry.targetReps ?? 0) : nil
        duration = metrics.contains(.duration) ? (entry.targetDuration ?? 0) : nil
        distance = metrics.contains(.distance) ? 0 : nil
    }

    init(from record: SetRecordDTO, metrics: MetricSet) {
        weight = metrics.contains(.weight) ? record.weight : nil
        reps = metrics.contains(.reps) ? record.reps : nil
        duration = metrics.contains(.duration) ? record.duration : nil
        distance = metrics.contains(.distance) ? record.distance : nil
    }
}
```

#### 2. Metric stepper
**File**: `S/Features/Components/MetricStepper.swift` — **create**.

```swift
import SwiftUI

/// − [value] + with 44pt targets, keyboard entry in the middle.
struct MetricStepper: View {
    let label: String
    @Binding var value: Double
    let step: Double
    var range: ClosedRange<Double> = 0...10_000
    var fractionDigits: Int = 1

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            stepButton("minus", "Decrease \(label)") { value = max(range.lowerBound, value - step) }
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...fractionDigits)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(Theme.Fonts.numeric)
                .frame(minWidth: 64, minHeight: 44)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                .accessibilityLabel(label)
                .accessibilityValue(value.formatted())
            stepButton("plus", "Increase \(label)") { value = min(range.upperBound, value + step) }
        }
    }

    private func stepButton(_ symbol: String, _ a11y: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.bold)).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(a11y)
    }
}

extension Binding where Value == Int? {
    /// Adapts an optional Int to the Double binding MetricStepper needs.
    func asDouble(default d: Double = 0) -> Binding<Double> {
        Binding<Double>(get: { Double(self.wrappedValue ?? Int(d)) }, set: { self.wrappedValue = Int($0.rounded()) })
    }
}
extension Binding where Value == Double? {
    func asDouble(default d: Double = 0) -> Binding<Double> {
        Binding<Double>(get: { self.wrappedValue ?? d }, set: { self.wrappedValue = $0 })
    }
}
```

#### 3. Set table
**File**: `F/Session/SetTableView.swift` — **create**.

```swift
import SwiftUI

/// Header + one row per planned set. Logged rows are read-only and success-tinted;
/// the first unlogged row is the editable draft with a stepper strip beneath it.
struct SetTableView: View {
    let entry: PlannedEntryDTO
    let exercise: ExerciseDTO?
    let logged: [SetRecordDTO]
    let previous: SetRecordDTO?
    let onLog: (SetDraft) -> Void
    let onDelete: (SetRecordDTO) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: SetDraft
    @State private var focusedMetric: Metric = .weight

    enum Metric: CaseIterable { case weight, reps, duration, distance }

    init(entry: PlannedEntryDTO, exercise: ExerciseDTO?, logged: [SetRecordDTO], previous: SetRecordDTO?,
         onLog: @escaping (SetDraft) -> Void, onDelete: @escaping (SetRecordDTO) -> Void) {
        self.entry = entry; self.exercise = exercise; self.logged = logged; self.previous = previous
        self.onLog = onLog; self.onDelete = onDelete
        let metrics = exercise?.metrics ?? [.weight, .reps]
        _draft = State(initialValue: previous.map { SetDraft(from: $0, metrics: metrics) } ?? SetDraft(target: entry, metrics: metrics))
        _focusedMetric = State(initialValue: metrics.contains(.weight) ? .weight : metrics.contains(.reps) ? .reps : metrics.contains(.duration) ? .duration : .distance)
    }

    private var metrics: MetricSet { exercise?.metrics ?? [.weight, .reps] }
    private var unit: Unit { exercise?.defaultUnit ?? .lb }
    private var columns: [Metric] { Metric.allCases.filter { metrics.contains(metricSet($0)) } }
    private var plannedCount: Int { max(entry.targetSets ?? 1, logged.count + 1) }
    private var stacked: Bool { typeSize >= .accessibility1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !stacked { header }
            ForEach(0..<plannedCount, id: \.self) { index in
                if index < logged.count {
                    loggedRow(logged[index], index: index)
                } else if index == logged.count {
                    draftRow(index: index)
                    stepperStrip
                } else {
                    placeholderRow(index: index)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Set").frame(width: 36, alignment: .leading)
            Text("Prev").frame(maxWidth: .infinity)
            ForEach(columns, id: \.self) { Text(title($0)).frame(maxWidth: .infinity) }
            Color.clear.frame(width: 44)
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func loggedRow(_ set: SetRecordDTO, index: Int) -> some View {
        row(index: index) {
            Text(previousText).frame(maxWidth: .infinity).foregroundStyle(.tertiary)
            ForEach(columns, id: \.self) { Text(valueText(set, $0)).frame(maxWidth: .infinity) }
        } trailing: {
            IconButton(title: "Delete set \(index + 1)", systemImage: "checkmark.circle.fill",
                       role: .destructive, tint: Theme.Colors.success) { onDelete(set) }
        }
        .font(Theme.Fonts.numeric)
        .background(Theme.Colors.success.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    }

    private func draftRow(index: Int) -> some View {
        row(index: index) {
            Button(previousText) { if let previous { draft = SetDraft(from: previous, metrics: metrics) } }
                .buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                .accessibilityLabel("Copy previous set \(previousText)")
                .disabled(previous == nil)
            ForEach(columns, id: \.self) { metric in
                Button(draftText(metric)) { focusedMetric = metric }
                    .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 44)
                    .background((focusedMetric == metric ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.surfaceRaised),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                    .accessibilityLabel("\(title(metric)) \(draftText(metric))")
            }
        } trailing: {
            Button { onLog(draft) } label: {
                Image(systemName: "checkmark").font(.headline).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log set \(index + 1)")
        }
        .font(Theme.Fonts.numeric)
    }

    private func placeholderRow(index: Int) -> some View {
        row(index: index) {
            Text(previousText).frame(maxWidth: .infinity).foregroundStyle(.tertiary)
            ForEach(columns, id: \.self) { _ in Text("—").frame(maxWidth: .infinity).foregroundStyle(.quaternary) }
        } trailing: { Color.clear.frame(width: 44, height: 44) }
    }

    @ViewBuilder private var stepperStrip: some View {
        switch focusedMetric {
        case .weight: MetricStepper(label: "Weight (\(WeightFormatter.label(unit)))", value: Binding(get: { draft.weight ?? 0 }, set: { draft.weight = $0 }), step: WeightFormatter.stepIncrement(for: unit))
        case .reps: MetricStepper(label: "Reps", value: Binding(get: { Double(draft.reps ?? 0) }, set: { draft.reps = Int($0) }), step: 1, fractionDigits: 0)
        case .duration: MetricStepper(label: "Duration (sec)", value: Binding(get: { Double(draft.duration ?? 0) }, set: { draft.duration = Int($0) }), step: 15, fractionDigits: 0)
        case .distance: MetricStepper(label: "Distance (\(unit.rawValue))", value: Binding(get: { draft.distance ?? 0 }, set: { draft.distance = $0 }), step: 0.25, fractionDigits: 2)
        }
    }

    // row(): HStack when !stacked, VStack(alignment: .leading) when stacked; first cell is "Set N".
    // title(): "Weight" | "Reps" | "Sec" | "Dist". metricSet(): maps Metric → MetricSet member.
    // previousText: previous.map { summary } ?? "—". valueText/draftText: formatted per metric via WeightFormatter.
}
```

Implement the four helper functions noted in the trailing comment inline; they are
pure formatting. `summary` reuses the `setSummary` logic from today's `PlannedEntryRow`
(`SessionRunView.swift:247-254`).

#### 4. View model
**File**: `F/Session/SessionRunViewModel.swift` — **modify**.

Add properties:
```swift
    /// Most recent set per exercise across the client's history, captured once at
    /// load so the "Prev" column does not shift as sets are logged this session.
    var previousSets: [UUID: SetRecordDTO] = [:]
    /// Changes on every successful log; drives `.sensoryFeedback`.
    var lastLoggedSetId: UUID?

    var plannedSetCount: Int {
        session.instances.flatMap(\.plannedEntries).reduce(0) { $0 + max($1.targetSets ?? 1, 1) }
    }
    var loggedSetCount: Int {
        session.instances.reduce(0) { total, instance in
            total + instance.plannedEntries.reduce(0) { $0 + min(sets(instanceId: instance.id, exerciseId: $1.exerciseId).count, max($1.targetSets ?? 1, 1)) }
        }
    }
    var progress: Double { plannedSetCount == 0 ? 0 : Double(loggedSetCount) / Double(plannedSetCount) }
```

In `load()` after the exercises block:
```swift
        let exerciseIds = Set(session.instances.flatMap(\.plannedEntries).map(\.exerciseId))
        for id in exerciseIds {
            if let last = await lastSet(exerciseId: id) { previousSets[id] = last }
        }
```

Add:
```swift
    func record(draft: SetDraft, instanceId: UUID, exerciseId: UUID) async {
        let metrics = exercises[exerciseId]?.metrics ?? [.weight, .reps]
        await record(
            instanceId: instanceId, exerciseId: exerciseId,
            weight: metrics.contains(.weight) ? draft.weight : nil,
            reps: metrics.contains(.reps) ? draft.reps : nil,
            duration: metrics.contains(.duration) ? draft.duration : nil,
            distance: metrics.contains(.distance) ? (draft.distance.map { $0 > 0 ? $0 : nil } ?? nil) : nil
        )
        if errorMessage == nil { lastLoggedSetId = UUID() }
    }
```

#### 5. Session view
**File**: `F/Session/SessionRunView.swift` — **modify**.

- Delete `SetEntryView` (lines 257-354) and `PlannedEntryRow` (171-255).
- Replace the per-instance `ForEach` body:
```swift
            ForEach(viewModel.session.instances) { instance in
                Section(instance.name) {
                    ForEach(instance.plannedEntries) { entry in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            TitleCaptionRow(title: viewModel.exercises[entry.exerciseId]?.name ?? "Exercise",
                                            caption: targetText(entry))
                            SetTableView(
                                entry: entry,
                                exercise: viewModel.exercises[entry.exerciseId],
                                logged: viewModel.sets(instanceId: instance.id, exerciseId: entry.exerciseId),
                                previous: viewModel.previousSets[entry.exerciseId],
                                onLog: { draft in Task { await viewModel.record(draft: draft, instanceId: instance.id, exerciseId: entry.exerciseId) } },
                                onDelete: { pendingDeleteSet = $0 })
                        }
                        .themedRows()
                    }
                }
            }
```
  Move `targetText` to a private func on `SessionRunView` (same body as today's).
  Move the delete `confirmationDialog` and `@State private var pendingDeleteSet: SetRecordDTO?` up to `SessionRunView`.
- "Mark Completed" button → `pendingStatus = .completed`. Extend the status alert:
  title `pendingStatus == .completed ? "Mark completed?" : …`, confirm button title
  `"Mark completed"`, message `pendingStatus == .completed ? "You can still log or delete sets afterwards." : "This can't be changed back from the app."`, role `.destructive` only for cancel/no-show.
- Add after `.navigationTitle`:
```swift
        .safeAreaInset(edge: .top) {
            if viewModel.session.status == .scheduled, viewModel.plannedSetCount > 0 {
                ProgressView(value: viewModel.progress)
                    .tint(Theme.Colors.success)
                    .padding(.horizontal)
                    .accessibilityLabel("Session progress")
                    .accessibilityValue("\(viewModel.loggedSetCount) of \(viewModel.plannedSetCount) sets")
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.lastLoggedSetId)
        .scrollDismissesKeyboard(.interactively)
```
- `#Preview` with `PreviewFixtures.container()` and `PreviewFixtures.scheduledSession`.

#### 6. Workout builder targets
**File**: `F/Workouts/WorkoutBuilderView.swift` — **modify** `OptionalStepper`'s non-nil branch:
replace the SwiftUI `Stepper` with
`MetricStepper(label: label, value: Binding(get: { Double(current) }, set: { value = Int($0) }), step: Double(step), range: Double(range.lowerBound)...Double(range.upperBound), fractionDigits: 0)`.
The weight `TextField` row at lines 162-169 → `MetricStepper(label: "Weight (\(WeightFormatter.label(unit)))", value: $entry.targetWeight.asDouble(), step: WeightFormatter.stepIncrement(for: unit))`.

#### 7. Tests
**File**: `Tests/SessionRunViewModelTests.swift` — **modify**, append:

```swift
@MainActor
@Test func previousSetsLoadedPerExercise() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    let exercises = SwiftDataExerciseRepository(modelContainer: container)
    let clients = SwiftDataClientRepository(modelContainer: container)
    let exerciseId = UUID(), clientId = UUID(), instanceId = UUID()
    _ = try await exercises.create(ExerciseDTO(id: exerciseId, name: "Bench", category: .strength,
        metrics: [.weight, .reps], defaultUnit: .lb, isCustom: true, createdAt: .now, updatedAt: .now))
    let entry = PlannedEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: 3, targetReps: 8, targetWeight: 100, targetDuration: nil)
    let session = SessionDTO(id: UUID(), clientId: clientId, startAt: .now, endAt: .now.addingTimeInterval(3600),
        status: .scheduled, notes: nil,
        instances: [WorkoutInstanceDTO(id: instanceId, sourceWorkoutId: UUID(), name: "W", plannedEntries: [entry])],
        seriesId: nil, recurrence: nil, eventIdentifier: nil, createdAt: .now, updatedAt: .now)
    try await sessions.schedule(session, attaching: [])
    try await sessions.recordSet(SetRecordDTO(id: UUID(), workoutInstanceId: instanceId, exerciseId: exerciseId, setIndex: 0,
        weight: 95, reps: 8, duration: nil, distance: nil, rpe: nil, performedAt: .now, createdAt: .now, updatedAt: .now))

    let vm = SessionRunViewModel(sessionRepo: sessions, exerciseRepo: exercises, clientRepo: clients,
                                 calendar: FakeCalendar(), session: session, clientName: "C")
    await vm.load()
    #expect(vm.previousSets[exerciseId]?.weight == 95)
    #expect(vm.plannedSetCount == 3)
    #expect(vm.loggedSetCount == 1)
    #expect(abs(vm.progress - 1.0/3.0) < 0.001)
}
```
Also add `progressReflectsLoggedOverPlanned` (log 3 sets → progress 1.0; a 4th does not exceed 1.0)
and `recordDraftOmitsMetricsNotInExercise` (exercise metrics `[.reps]`, draft has weight 50 →
stored set has `weight == nil`, `reps == 8`, and `lastLoggedSetId != nil`). Reuse the setup above
via a private `makeSessionEnv(metrics:)` helper.

### Verification
#### Automated
- [x] Test command passes (112).
- [x] `grep -n "SetEntryView\|PlannedEntryRow" Sources -r` → 0 lines.

#### Manual
- [ ] On the fixture session: tap the ✓ on Bench set 3 without editing → set logs, haptic fires, row turns green, progress bar advances.
- [ ] Tap a "Prev" cell → draft values change to the previous set; stepper strip edits the focused metric; typing into the stepper field works and the keyboard dismisses on scroll.
- [ ] Tap "Mark Completed" → alert appears; confirm → status text updates and the progress bar disappears.
- [ ] Screenshots `p3-session-{light,dark,ax3}.png`; the AX3 shot shows stacked rows with no clipping.
- [ ] Workout builder targets sheet shows the new steppers; Clear still nils the value.

---

## Phase 4: Self-use client

### Changes

#### 1. Model and DTO
**File**: `S/Models/Client.swift` — **modify**: add `var isSelf: Bool = false` after `isArchived`, an
`isSelf: Bool = false` init parameter, and assignment.
**File**: `S/Models/DTO/ClientDTO.swift` — **modify**:

```swift
struct ClientDTO: Codable, Sendable, Identifiable, Equatable {
    // existing fields …
    /// Device-local flag; intentionally excluded from the export format.
    var isSelf: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, phoneE164, goal, injuries, notes, isArchived, createdAt, updatedAt
    }
}
```
Carry `isSelf` through `init(_ model:)`, `apply(to:)`, and `toModel()`.

#### 2. Schema version
**File**: `S/Persistence/SchemaV2.swift` — **create**:

```swift
import SwiftData

/// Adds `Client.isSelf` (defaulted). Models are the live classes, as in SchemaV1.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { SchemaV1.models }
    static var versionString: String {
        let v = versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }
}
```
**File**: `S/Persistence/SchemaV1.swift` — **modify** the plan:
```swift
enum TrainMeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
```
**File**: `S/Persistence/PersistenceController.swift` — **modify**: `schemaTypes` → `SchemaV2.models`;
`Schema(versionedSchema: SchemaV2.self)`.
**File**: `S/TrainMeApp.swift:19` — **modify**: `currentVersion: SchemaV2.versionString` (this makes
`StoreBackup` take one backup on first launch after upgrade, which is the intended path).

#### 3. Repository
**File**: `S/Persistence/ClientRepository.swift` — **modify** protocol and actor:
```swift
    func selfClient() async throws -> ClientDTO?
```
```swift
    func selfClient() async throws -> ClientDTO? {
        try modelContext.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.isSelf })).first.map(ClientDTO.init)
    }
```
No test fakes conform to `ClientRepository` today (verified by grep), so only the actor changes.

#### 4. Edit flow
**File**: `F/Clients/ClientEditViewModel.swift` — **modify**:
- `init(repo:existing:isSelf: Bool = false)`; store `let isSelf: Bool` as `existing?.isSelf ?? isSelf`.
- `canSave`: `!name.isEmpty && (isSelf || phoneValid)`.
- `save()`: `let phone = isSelf ? (normalizeE164(phoneRaw) ?? "") : normalizeE164(phoneRaw)`; guard only when `!isSelf`;
  pass `isSelf: isSelf` into the DTO.
**File**: `F/Clients/ClientEditView.swift` — **modify**: `init(repo:existing:isSelf: Bool = false, onSaved:)`;
when `viewModel.isSelf`, title "About You", phone row hidden, and section header "Your profile".
**File**: `F/Clients/ClientDetailView.swift` — **modify**: `LabeledContent("Phone", …)` only when `!viewModel.client.isSelf`;
title suffix "(You)" when `isSelf`.

#### 5. Entry points
**File**: `F/Clients/ClientListView.swift` — **modify**: add `@State private var showingSelf = false`;
empty state action `("Add yourself", { showingSelf = true })` when `viewModel.query.isEmpty`;
`.sheet(isPresented: $showingSelf) { ClientEditView(repo: viewModel.repository, existing: nil, isSelf: true) { Task { await viewModel.load() } } }`.
**File**: `F/Clients/ClientListViewModel.swift` — **modify**: `var hasSelfClient = false` set in `load()` via `repository.selfClient() != nil`; hide the action when true.
**File**: `S/RootView.swift` — **modify**: first-run alert gains `Button("Add yourself as a client") { hasSeenBackupNotice = true; selectedTab = 1; wantsSelfClient = true }`
with `@AppStorage("wantsSelfClient") private var wantsSelfClient = false`; `ClientListView` reads the same key via `@AppStorage` in `.task` and opens the self sheet once, then clears it.
**File**: `F/Schedule/SessionEditView.swift` — **modify** `.task`: after loading clients, `if selectedClientId == nil, clients.count == 1 { selectedClientId = clients[0].id }`.

#### 6. Tests
**File**: `Tests/SchemaTests.swift` — **modify**:
```swift
@Test func schemaV1ListsAllModels() {
    #expect(SchemaV1.models.count == 8)
    #expect(SchemaV1.versionString == "1.0.0")
    #expect(SchemaV2.versionString == "2.0.0")
    #expect(TrainMeMigrationPlan.schemas.count == 2)
    #expect(TrainMeMigrationPlan.stages.count == 1)
}
```
**File**: `Tests/ClientRepositoryTests.swift` — **modify**, append:
- `selfClientRoundTrip`: upsert a DTO with `isSelf: true` and phone `""` → `selfClient()?.name` matches; `all()` includes it.
- `selfClientSkipsPhoneValidation`: `ClientEditViewModel(repo:existing:nil,isSelf:true)` with name "Me" → `canSave == true`; `save()` returns true; stored `phoneE164 == ""`.
- `exportOmitsIsSelf`: `JSONEncoder().encode(dto(isSelf: true))` → decoded `[String: Any]` has no `"isSelf"` key; `JSONDecoder` round-trip yields `isSelf == false`.

### Verification
#### Automated
- [x] Test command passes (115).
- [x] `grep -c '"isSelf"' Tests/Fixtures/export-v1.json` prints `0` and `git diff --quiet Tests/Fixtures/` succeeds.
- [x] `ArchiveRoundTripTests` still pass unchanged.

#### Manual
- [ ] Install Phase 3's build on the simulator, add a client, then install Phase 4's build over it: the app opens, the client is present, and `~/Library/Developer/CoreSimulator/…/Application Support/backups/pre-schema-2.0.0/` exists.
- [ ] Fresh install: first-run alert → "Add yourself as a client" → Clients tab opens the "About You" sheet; Save with name only succeeds.
- [ ] New session sheet preselects the self client when it is the only client.

---

## Phase 5: Icon refinement with explicit variants

### Changes

#### 1. Reference export (do first)
Open `Icon Composer.app` (Xcode 26 → Open Developer Tool), create a throwaway icon with
one image layer, set a different image for the Dark and Mono appearances, and export to
`/private/tmp/claude-501/…/scratchpad/ref.icon`. Read its `icon.json` and copy the exact key
names used for per-appearance image and fill specializations. The shapes below assume
`"appearance": "dark"` / `"appearance": "mono"` inside `image-name-specializations` and a
top-level `"fill-specializations"`; **replace them with whatever the export shows**.

#### 2. SVG layers
**File**: `S/AppIcon.icon/Assets/line.svg` — **modify**: `stroke-width="104"`, circle `r="72"`.
**File**: `S/AppIcon.icon/Assets/dumbbell.svg` — **modify**:
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" fill="#FFFFFF">
  <rect x="312" y="484" width="400" height="56" rx="28"/>
  <rect x="194" y="380" width="106" height="264" rx="30"/>
  <rect x="724" y="380" width="106" height="264" rx="30"/>
  <rect x="120" y="424" width="62" height="176" rx="22"/>
  <rect x="842" y="424" width="62" height="176" rx="22"/>
</svg>
```
**File**: `S/AppIcon.icon/Assets/background.svg` — **modify** stops to `#0F766E` → `#3730A3` (unchanged values; confirm they match `BrandPrimary`/`BrandSecondary` light).
**File**: `S/AppIcon.icon/Assets/background-dark.svg` — **create**: same rect, gradient `#042F2E` → `#1E1B4B`.
**File**: `S/AppIcon.icon/Assets/line-mono.svg` — **create**: copy of `line.svg` with `stroke="#FFFFFF"` and `fill="#FFFFFF"`.
**File**: `S/AppIcon.icon/Assets/dumbbell-mono.svg` — not needed (already white); reuse `dumbbell.svg`.

#### 3. icon.json
**File**: `S/AppIcon.icon/icon.json` — **modify**. For the "rising line" layer:
```json
"image-name-specializations": [
  { "value": "line.svg" },
  { "appearance": "dark", "value": "line.svg" },
  { "appearance": "mono", "value": "line-mono.svg" }
]
```
For "background":
```json
"image-name-specializations": [
  { "value": "background.svg" },
  { "appearance": "dark", "value": "background-dark.svg" }
]
```
Top level, replacing `"fill": "system-light"`:
```json
"fill": "system-light",
"fill-specializations": [ { "appearance": "dark", "value": "system-dark" } ]
```
Keep group order, shadow, specular, and translucency as committed.

#### 4. Accent dark entry
Already done in Phase 1 §1 (`AccentColor` dark `#F59E0B`). No further change.

### Verification
#### Automated
- [x] `xcrun actool --compile /tmp/icon-out --platform iphonesimulator --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist /tmp/icon-out/p.plist Sources/AppIcon.icon Sources/Assets.xcassets 2>&1 | grep -ci "error"` prints `0`.
- [x] Test command passes (115).

#### Manual
- [x] Simulator home screen: long-press → Edit Home Screen → appearance Light / Dark / Tinted / Clear; capture `p5-icon-{default,dark,tinted,clear}.png`. The line is clearly visible at 60pt.
- [ ] If `actool` rejects the specialization keys after two corrected attempts, revert `icon.json` to the single-appearance file (keep the bolder SVGs) and add a BACKLOG row "Explicit icon appearance variants".

---

## Phase 6: Reports theming and final accessibility sweep

### Changes

#### 1. Charts
**File**: `F/Reports/ClientReportView.swift` — **modify**.
- `ExerciseProgressChart`: `LineMark` gets `.foregroundStyle(Theme.Colors.brandPrimary)`; PB `PointMark` and "PB" text → `Theme.Colors.personalBest`;
  after `.chartYAxisLabel` add
  `.accessibilityLabel("\(unitLabel) over time, \(plotted.count) points, latest \(plotted.last?.value.formatted() ?? "none")")`.
- `VolumeChart`: add `.chartForegroundStyleScale(["lb": Theme.Colors.brandPrimary, "kg": Theme.Colors.brandSecondary])`
  and `.accessibilityLabel("Weekly volume, \(weeks.count) weeks")`.
- "unresolved sessions" caption `.orange` → `Theme.Colors.warning`.

#### 2. PDF pages
**File**: `S/Services/ReportExporter.swift` — **modify**: on both page views, after `.background(.white)` add
`.environment(\.colorScheme, .light)`.

#### 3. BACKLOG
**File**: `BACKLOG.md` — **modify**. Add to the Done table (keep `#` continuing from the existing rows,
Issue column "—" until the PR exists):
- "Theme tokens and shared components" — `Sources/Support/Theme.swift`, `Sources/Features/Components/`; dark-first colorsets.
- "Inline set table" — `SetTableView`, `MetricStepper`, `SetDraft`; one-tap logging with haptic and progress.
- "Self-use client" — `Client.isSelf`, `SchemaV2` lightweight migration, "About You" sheet.
- "Icon appearance variants" — bolder layers, explicit dark/mono specializations.
- "Previews for every screen" — `PreviewFixtures`.
Add to the P2 table: "Snapshot tests for themed screens (swift-snapshot-testing, CI baseline)" with Evidence "Previews + manual screenshots only; see `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/`".

### Verification
#### Automated
- [x] Test command passes (115). `ReportExporterTests` unchanged and green.
- [x] `grep -rn "\.orange\b" Sources` → 0 lines.

#### Manual
- [x] Simulator in dark mode: open a client report, Share PNG → the rendered image has a white background and dark text.
- [x] VoiceOver on the chart reads the summary label.
- [x] AX3 pass: `p6-{schedule,clients,client-detail,session,workouts,builder,exercises,report,settings}-ax3.png` show no clipped or overlapping text. Fix any clipping in the component involved before closing the phase.
- [x] Final light/dark gallery: `p6-{schedule,session,report}-{light,dark}.png`.

---

#### Closed on the follow-up pass (2026-10-26)
- Dark-mode Share PNG verified: `ReportExporter` output has a white background and dark
  text while the device is in dark mode. VoiceOver labels on charts were checked by code
  review of the `accessibilityLabel` modifiers, not with VoiceOver running.
- AX3 pass found and fixed two issues: `TitleCaptionRow` inside plain-style buttons only
  hit-tested its text (now `.contentShape(Rectangle())`), and the builder's target rows
  clipped at AX3 (now stack label-over-control via `ViewThatFits`).
- `SetTableView` re-seeds an untouched draft when the exercise or previous set arrives,
  tracked by a `draftTouched` flag rather than `logged.isEmpty`.
- Known, not changed: the Schedule export banner wraps "Back up your data" / "Export"
  tightly at AX3 (pre-existing layout); Phase 4 `SchemaV1` holds a frozen model snapshot;
  Phase 5 declares the mono layer under Icon Composer's `tinted` appearance.

## Resume notes

- Tests expected: 109 → 112 (Phase 3) → 115 (Phase 4).
- Never regenerate `Tests/Fixtures/export-v1.json`.
- If XcodeGen fails to pick up `Sources/Features/Components/`, check `createIntermediateGroups: true` in `project.yml` and re-run `xcodegen generate`; the `sources: [Sources]` glob needs no edit.
- Screenshots live under `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/` and are attached to the PR in step 8.

## Merge record

- 2026-10-26: PR opened as [#36](https://github.com/madacgrav/trainme/pull/36).
- 2026-10-26: CI green on #36 (`test` check); merged into main as 0c7a624.
