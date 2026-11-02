# Implementation Plan — Quick timers with Apple Watch (GH #38)

## Overview

The session run screen gets one-tap timers:
- Logging a set auto-starts a rest countdown. The default length comes from Settings, and you can quick-pick 60/90/120 s, add 15 s, or skip.
- Duration exercises get a **Start** countdown that prefills the draft's seconds at zero. It never auto-logs.
- Timers survive backgrounding, the app lock and relaunch, and a notification fires at zero.

A companion watch app then mirrors the timer, can start or extend or skip it, can start the phone's **Up next** timed set, and owns the wrist cue.

**Conventions.**
- `S/` = `Sources/`, `T/` = `Tests/`, `SH/` = `Shared/` (new, compiled into both app targets), `W/` = `Watch/` (new).
- Stack: Swift 6 strict concurrency, iOS 26 / watchOS 26, SwiftUI, Swift Testing, XcodeGen 2.46.
- Base: `main` at d47fea0.

Every phase ends green on:

```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```

**Project files.** `TrainMe.xcodeproj` is generated and gitignored, so never edit it by hand. New files under a target's `sources` folders are picked up automatically. If `xcodegen` is missing, stop and ask the user (`brew install xcodegen`).

**Device build and install** (madphone, UDID `00008140-001E31AE21DB001C`):

```bash
xcodebuild -project TrainMe.xcodeproj -scheme TrainMe -configuration Debug -destination 'id=00008140-001E31AE21DB001C' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-001E31AE21DB001C build/DerivedData/Build/Products/Debug-iphoneos/TrainMe.app
xcrun devicectl device process launch --device 00008140-001E31AE21DB001C com.madacgrav.trainme
```

From Phase 4 on, the watch app is embedded in `TrainMe.app` and installs to the paired watch with the phone app. Check it in the Watch app → My Watch → TrainMe if it doesn't appear.

**Baseline.** `grep -r "@Test" Tests | wc -l` gives 152.

**Untouched.**
- Schema, DTOs, repositories, archive, `NotificationService.swift`.
- `LockGateView`'s teardown and `RootView.swift`.
- The `SessionRunViewModel` init signature.

**Rules for all phases:**
- Timer state is always derived from `endAt` and the **injected** `now`. Never count ticks, and never call `Date()` directly inside `TimerStore` or `TimerMath`.
- Notification ids for timers use the prefix `timer-` only. Never touch `sess-` requests.
- Any `#Preview` that renders `SessionRunView`, `SetTableView` or `TimerBar` adds `.environment(TimerStore.preview)`. `@Environment(TimerStore.self)` traps without it.
- Swift 6: OS delegate callbacks are `nonisolated`. Extract plain values, then hop with `Task { @MainActor in … }`. Wire payloads are `Codable` → `Data` under a single `"payload"` key, never raw `[String: Any]` trees.

**Deviations from structure.md** (each keeps the same behaviour):
1. Rest auto-start hooks `SessionRunView.onChange(of: viewModel.lastLoggedSetId)` instead of a new `onSetLogged` init parameter. `lastLoggedSetId` already changes only on a successful log (tested at `T/SessionRunViewModelTests.swift:360-371`), so the view model stays free of `TimerStore`.
2. The app-level `scenePhase` hook lives in `TrainMeApp`, not `RootView`, so `RootView` stays untouched.
3. The watch uses a generated Info.plist (`INFOPLIST_KEY_*` settings) instead of a hand-written `W/Info.plist`.
4. Watch→phone commands are `adopt(ActiveTimer)` and `skip(timerId:)`, not `startRest`/`startUpNext`/`extend`. The watch builds the timer itself from shared `TimerMath`, so the same message works whether or not the phone is reachable (`sendMessage` or queued `transferUserInfo`), and the phone needs no clock translation.

---

## Phase 1: Rest timer on the phone (in memory)

### Changes

#### 1. Compile `Shared/` into the app
**File**: `project.yml` · **Action**: modify

```yaml
  TrainMe:
    type: application
    platform: iOS
    sources: [Sources, Shared]
```

#### 2. Timer value types
**File**: `SH/Timer/ActiveTimer.swift` · **Action**: create

```swift
import Foundation

enum TimerKind: Codable, Sendable, Equatable {
    case rest
    case timedSet(plannedEntryId: UUID, instanceId: UUID)
}

/// One running countdown. Remaining time is always derived from `endAt`.
struct ActiveTimer: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var kind: TimerKind
    var startedAt: Date
    var endAt: Date

    /// Total length including any extensions; used to prefill a timed set.
    var seconds: Int { Int(endAt.timeIntervalSince(startedAt).rounded()) }

    var isRest: Bool { kind == .rest }
}
```

**File**: `SH/Timer/TimerMath.swift` · **Action**: create

```swift
import Foundation

enum TimerMath {
    static let quickPicks = [60, 90, 120]
    static let extendStep = 15
    static let defaultRest = 90

    static func make(kind: TimerKind, seconds: Int, now: Date) -> ActiveTimer {
        ActiveTimer(id: UUID(), kind: kind, startedAt: now, endAt: now.addingTimeInterval(TimeInterval(seconds)))
    }

    static func remaining(_ timer: ActiveTimer, now: Date) -> TimeInterval { max(0, timer.endAt.timeIntervalSince(now)) }

    static func isComplete(_ timer: ActiveTimer, now: Date) -> Bool { now >= timer.endAt }

    /// Adds time to the end; a timer already at zero restarts from now.
    static func extended(_ timer: ActiveTimer, by seconds: Int, now: Date) -> ActiveTimer {
        var copy = timer
        copy.endAt = max(timer.endAt, now).addingTimeInterval(TimeInterval(seconds))
        return copy
    }

    /// One timer at a time: a rest may not replace a running timed set.
    static func canReplace(_ current: ActiveTimer?, with next: ActiveTimer, now: Date) -> Bool {
        guard let current, current.id != next.id, !isComplete(current, now: now) else { return true }
        return !(next.isRest && !current.isRest)
    }
}
```

#### 3. TimerStore
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: create

```swift
import Foundation
import Observation

enum TimerSettings {
    static let defaultRestKey = "defaultRestSeconds"
    static let restChoices = [30, 45, 60, 90, 120, 150, 180]
}

/// App-level owner of the single running timer. Lives above `LockGateView`
/// (which tears down its content on background) so timers survive the lock.
@MainActor
@Observable
final class TimerStore {
    private(set) var active: ActiveTimer?
    /// Bumps on every natural completion; drives `.sensoryFeedback`.
    private(set) var completionTick = 0

    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let autoComplete: Bool
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init(autoComplete: Bool = true, now: @escaping @Sendable () -> Date = { Date() }) {
        self.autoComplete = autoComplete
        self.now = now
    }

    static var preview: TimerStore { TimerStore(autoComplete: false) }

    func startRest(seconds: Int) {
        start(TimerMath.make(kind: .rest, seconds: seconds, now: now()))
    }

    func extend(by seconds: Int = TimerMath.extendStep) {
        guard let active else { return }
        set(TimerMath.extended(active, by: seconds, now: now()))
    }

    func skip() { set(nil) }

    /// Completes the timer if its end has passed. Called by the watcher and on `.active`.
    func refresh() {
        guard let active, TimerMath.isComplete(active, now: now()) else { return }
        complete(active)
    }

    // MARK: - Private

    /// Returns false when the one-timer rule rejects `timer`.
    @discardableResult
    private func start(_ timer: ActiveTimer) -> Bool {
        guard TimerMath.canReplace(active, with: timer, now: now()) else { return false }
        set(timer)
        return true
    }

    private func complete(_ timer: ActiveTimer) {
        set(nil)
        completionTick += 1
    }

    /// Single mutation point; later phases add persist / notify / sync here.
    private func set(_ timer: ActiveTimer?) {
        active = timer
        armWatcher()
    }

    private func armWatcher() {
        watcher?.cancel()
        watcher = nil
        guard autoComplete, let end = active?.endAt else { return }
        let delay = max(0, end.timeIntervalSince(now()))
        watcher = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
```

#### 4. Own the store above the lock and play the zero haptic
**File**: `S/TrainMeApp.swift` · **Action**: modify

```swift
@main
struct TrainMeApp: App {
    @State private var bootstrap = AppBootstrap()
    @State private var timers = TimerStore()

    var body: some Scene {
        WindowGroup {
            switch bootstrap.state {
            case .ready(let container):
                LockGateView {
                    RootView(container: container)
                }
                .environment(timers)
                .sensoryFeedback(.warning, trigger: timers.completionTick)
            case .failed(let message):
                // unchanged
```

#### 5. Timer bar
**File**: `S/Features/Timer/TimerBar.swift` · **Action**: create

This is a compact bar for `safeAreaInset(edge: .bottom)`.
- **Idle**: a `Menu("Rest", systemImage: "timer")` listing `TimerMath.quickPicks` as "60 s" etc. → `timers.startRest(seconds:)`.
- **Running**:
  - Kind label: "Rest" or "Timed set".
  - `Text(timerInterval: t.startedAt...t.endAt, countsDown: true).monospacedDigit().font(Theme.Fonts.numeric)`.
  - For rest only: a quick-pick `Menu` (restarts the rest at that length).
  - `Button("+15 s") { timers.extend() }` and `Button("Skip") { timers.skip() }`.
  - Under the row: `ProgressView(timerInterval: t.startedAt...t.endAt, countsDown: true)` tinted `Theme.Colors.accent`.
- Background `.bar`, padding `Theme.Spacing.sm`. Buttons ≥ 44 pt. Add `accessibilityLabel`s such as "Rest timer, 1 minute 12 seconds left" via `.accessibilityElement(children: .combine)` on the label group.
- Add a `#Preview` with `TimerStore.preview` that calls `startRest(seconds: 90)` first.

#### 6. Run screen wiring
**File**: `S/Features/Session/SessionRunView.swift` · **Action**: modify

```swift
    @Environment(TimerStore.self) private var timers
    @AppStorage(TimerSettings.defaultRestKey) private var defaultRestSeconds = TimerMath.defaultRest
```

On the `List` chain, next to the existing `.sensoryFeedback(.success, …)`:

```swift
        .safeAreaInset(edge: .bottom) {
            if viewModel.session.status == .scheduled { TimerBar() }
        }
        // A successful log starts the rest countdown (lastLoggedSetId changes only on success).
        .onChange(of: viewModel.lastLoggedSetId) { _, id in
            if id != nil { timers.startRest(seconds: defaultRestSeconds) }
        }
```

The `#Preview("Session")` adds `.environment(TimerStore.preview)` on the `NavigationStack`. Also add it to the `ScheduleView` and `ClientDetailView` previews (their links build `SessionRunView`). Find them with `grep -n "#Preview" S/Features/Schedule/ScheduleView.swift S/Features/Clients/ClientDetailView.swift`.

#### 7. Settings default
**File**: `S/Features/Settings/SettingsView.swift` · **Action**: modify

```swift
    @AppStorage(TimerSettings.defaultRestKey) private var defaultRestSeconds = TimerMath.defaultRest
```

Add a new `Section` right after "Units":

```swift
                Section {
                    Picker("Default rest", selection: $defaultRestSeconds) {
                        ForEach(TimerSettings.restChoices, id: \.self) { Text("\($0) s").tag($0) }
                    }
                } header: {
                    Text("Timers")
                } footer: {
                    Text("Logging a set starts a rest countdown of this length.")
                }
```

#### 8. Tests
**File**: `T/TimerMathTests.swift` · **Action**: create
- `remainingNeverNegative`: past the end → 0.
- `extendFromFutureEndAddsToEnd`: endAt +15.
- `extendAfterZeroRestartsFromNow`: endAt = now + 15.
- `secondsIncludesExtensions`: 45 + 15 → 60.
- `restCannotReplaceRunningTimedSet`; `timedSetReplacesRest`; `anythingReplacesCompletedTimer`; `sameIdAlwaysReplaces`.

**File**: `T/TimerStoreTests.swift` · **Action**: create

```swift
import Foundation
import Testing
@testable import TrainMe

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func makeStore(_ clock: TestClock) -> TimerStore {
    TimerStore(autoComplete: false, now: { clock.now })
}
```

- `startRestSetsEndFromNow`: `active?.endAt == clock.now + 90`.
- `refreshBeforeEndDoesNothing`: tick stays 0 and the timer is kept.
- `refreshAfterEndCompletes`: active is nil and tick is 1.
- `skipClearsWithoutCompletion`: tick stays 0.
- `extendAddsFifteen`.
- `newRestReplacesRest`: the new id wins.

### Verification
#### Automated
- [x] Phase test command passes; `grep -r "@Test" Tests | wc -l` ≥ 166.
- [x] `grep -rn "Date()" S/Features/Timer SH/Timer` matches only the default `now:` argument in `TimerStore.init`.

#### Manual (simulator)
- [x] Open a scheduled session and log a set: the bar counts down from the Settings default (90).
- [x] +15 s, Skip and the quick picks behave. At zero the bar returns to idle (the haptic only plays on a device).
- [x] Changing Settings → Timers → Default rest to 60 makes the next log start a 60 s rest.

---

## Phase 2: Timers survive background, lock and relaunch

### Changes

#### 1. Timer notifications
**File**: `S/Services/TimerNotificationService.swift` · **Action**: create

```swift
import Foundation
import UserNotifications

let timerNotificationPrefix = "timer-"

func timerNotificationIdentifier(_ id: UUID) -> String { timerNotificationPrefix + id.uuidString }

func timerNotificationIdentifiers(from pending: [String]) -> [String] {
    pending.filter { $0.hasPrefix(timerNotificationPrefix) }
}

func timerNotificationText(for kind: TimerKind) -> (title: String, body: String) {
    switch kind {
    case .rest: ("Rest over", "Time for the next set.")
    case .timedSet: ("Timed set done", "Log the set in TrainMe.")
    }
}

protocol TimerNotifying: Sendable {
    func schedule(_ timer: ActiveTimer) async
    func cancelAll() async
}

struct LocalTimerNotifier: TimerNotifying {
    func schedule(_ timer: ActiveTimer) async {
        let center = UNUserNotificationCenter.current()
        guard canScheduleAlerts(await center.notificationSettings().authorizationStatus) else { return }
        let interval = timer.endAt.timeIntervalSinceNow
        guard interval >= 1 else { return }
        let text = timerNotificationText(for: timer.kind)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: timerNotificationIdentifier(timer.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do { try await center.add(request) } catch {
            Log.notifications.error("timer alert failed: \(error.localizedDescription)")
        }
    }

    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: timerNotificationIdentifiers(from: pending))
    }
}
```

#### 2. Persist, restore and notify in the store
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: modify

```swift
    static let storageKey = "activeTimer"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: any TimerNotifying
    /// Serialises async side effects so cancel/schedule never interleave.
    @ObservationIgnored private var outbox: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         notifier: any TimerNotifying = LocalTimerNotifier(),
         autoComplete: Bool = true,
         now: @escaping @Sendable () -> Date = { Date() }) {
        // assign …
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(ActiveTimer.self, from: data),
           !TimerMath.isComplete(saved, now: now()) {
            active = saved   // the pending notification from before is still valid
            armWatcher()
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    static var preview: TimerStore {
        TimerStore(defaults: UserDefaults(suiteName: "TimerPreview")!, notifier: NoopTimerNotifier(), autoComplete: false)
    }

    /// Test hook: waits for queued side effects.
    func flush() async { await outbox?.value }

    private func set(_ timer: ActiveTimer?) {
        active = timer
        persist()
        armWatcher()
        enqueue { [notifier] in
            await notifier.cancelAll()
            if let timer { await notifier.schedule(timer) }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = outbox
        outbox = Task { await previous?.value; await work() }
    }

    private func persist() {
        if let active, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
```

A timer that completed while the app was dead is dropped silently on restore (no late haptic). Its notification has already fired.

`NoopTimerNotifier` is a `struct` in the same file with empty bodies. It is used by previews.

#### 3. Recompute on foreground
**File**: `S/TrainMeApp.swift` · **Action**: modify

```swift
    @Environment(\.scenePhase) private var scenePhase
    // …on the WindowGroup content (outside the switch, e.g. wrap the switch in a Group):
        .onChange(of: scenePhase) { _, phase in
            // Not .inactive: Face ID drops the app to .inactive (LockGateView.swift:3-4).
            if phase == .active { timers.refresh() }
        }
```

`refresh()` completes an overdue timer (the haptic plays and the bar clears), or re-arms the watcher for the remainder. Add `armWatcher()` at the end of `refresh()` when the timer is not complete, so a watcher suspended in the background restarts.

#### 4. Tests
**File**: `T/TimerNotificationTests.swift` · **Action**: create
- `identifiersUsePrefix`.
- `onlyTimerIdentifiersSelected`: a mix with `sess-…-1h` keeps only `timer-…`.
- `textPerKind`.

**File**: `T/TimerStoreTests.swift` · **Action**: modify

Add `actor FakeTimerNotifier: TimerNotifying` with `scheduled: [UUID]` and `cancelCount`. `makeStore` takes `defaults: UserDefaults(suiteName: "timer-\(UUID())")!` and the fake. Tests:
- `startPersistsAndRestores`: a second store on the same defaults restores the same id.
- `completedTimerNotRestored`.
- `skipRemovesPersisted`.
- `startSchedulesAfterCancel`: `await store.flush()`, then `cancelCount == 1` and `scheduled == [id]`.
- `skipCancelsWithoutScheduling`.
- `extendReschedulesSameId`.

### Verification
#### Automated
- [x] Phase test command passes; `@Test` count ≥ 175.
- [x] `grep -rn "sess-" S/Features/Timer S/Services/TimerNotificationService.swift` → no code matches (one doc comment).

#### Manual (device, madphone)
- [x] Start a rest and lock the phone: the notification "Rest over" arrives at zero. (Verified on the iPhone 17 simulator; watch mirroring not yet checked on a real device.)
- [x] Mid-rest, background the app, then return: after the unlock the bar shows the correct remaining time.
- [x] Mid-rest, swipe-kill the app and relaunch: open the session and the bar shows the remaining time.
- [x] Skip a rest, then lock the phone: no notification.

---

## Phase 3: Timed-set countdown with prefill

### Changes

#### 1. Completion event and timed start
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: modify

```swift
struct TimerCompletion: Equatable, Sendable {
    let timerId: UUID
    let kind: TimerKind
    let seconds: Int
}

    /// Set on natural completion only (skip never sets it).
    private(set) var lastCompletion: TimerCompletion?

    func startTimedSet(plannedEntryId: UUID, instanceId: UUID, seconds: Int) {
        guard seconds > 0 else { return }
        start(TimerMath.make(kind: .timedSet(plannedEntryId: plannedEntryId, instanceId: instanceId),
                             seconds: seconds, now: now()))
    }

    private func complete(_ timer: ActiveTimer) {
        set(nil)
        lastCompletion = TimerCompletion(timerId: timer.id, kind: timer.kind, seconds: timer.seconds)
        completionTick += 1
    }
```

#### 2. Pure prefill
**File**: `S/Features/Session/SetDraft.swift` · **Action**: modify

```swift
    /// Countdown result → draft; a no-op for exercises that don't track duration.
    func prefilled(duration: Int, metrics: MetricSet) -> SetDraft {
        guard metrics.contains(.duration) else { return self }
        var copy = self
        copy.duration = duration
        return copy
    }
```

#### 3. Countdown control in the set table
**File**: `S/Features/Session/SetTableView.swift` · **Action**: modify
- New stored property and init parameter `onStartTimer: ((Int) -> Void)? = nil`, as the last parameter, defaulted so existing call sites compile.
- `@Environment(TimerStore.self) private var timers`.
- Add a helper:
  ```swift
  private var countdownRunningHere: Bool {
      if case .timedSet(let id, _) = timers.active?.kind { id == entry.id } else { false }
  }
  ```
- In `body`, in the `index == logged.count` branch, between `draftRow` and the stepper strip:
  ```swift
  if metrics.contains(.duration), let onStartTimer { countdownControl(onStartTimer) }
  ```
- `countdownControl`:
  - Running here: `Button("Stop", systemImage: "stop.fill") { timers.skip() }`.
  - Otherwise: `Button("Start \(draft.duration ?? 0) s countdown", systemImage: "timer") { onStartTimer(draft.duration ?? 0) }`, `.disabled((draft.duration ?? 0) <= 0)`.
  - Style `.bordered`, minHeight 44, full width.
- Add to the modifiers:
  ```swift
  .onChange(of: timers.lastCompletion) { _, completion in
      guard let completion, case .timedSet(let id, _) = completion.kind, id == entry.id else { return }
      draft = draft.prefilled(duration: completion.seconds, metrics: metrics)
      draftTouched = true
      focusedMetric = .duration
  }
  ```
- Add `.environment(TimerStore.preview)` to `#Preview("Set table")`.

#### 4. Pass the start closure
**File**: `S/Features/Session/SessionRunView.swift` · **Action**: modify. In the `SetTableView(...)` call:

```swift
                                onDelete: { pendingDeleteSet = $0 },
                                onStartTimer: { seconds in
                                    timers.startTimedSet(plannedEntryId: entry.id, instanceId: instance.id, seconds: seconds)
                                }
```

#### 5. Tests
**File**: `T/TimerStoreTests.swift` · **Action**: modify
- `timedSetCompletionCarriesEntryAndSeconds`: start 45, advance 46, refresh → `lastCompletion?.seconds == 45` with the matching entry id.
- `extendedTimedSetReportsTotal`: 45 + 15 → 60.
- `skipTimedSetEmitsNoCompletion`.
- `restDuringTimedSetIsIgnored`.
- `timedSetReplacesRest`.
- `zeroSecondTimedSetIgnored`.

**File**: `T/SetDraftPrefillTests.swift` · **Action**: create
- `prefillSetsDuration`.
- `prefillIgnoredWithoutDurationMetric`.
- `prefillKeepsOtherMetrics`.

### Verification
#### Automated
- [x] Phase test command passes; `@Test` count ≥ 184.

#### Manual (simulator + device)
- [x] Plank entry: the draft row shows "Start 30 s countdown" (from a 30 s `targetDuration`). Start, +15 s → the bar shows "Timed set" → at zero the Sec cell reads 45 and nothing is logged.
- [x] Tap ✓ → the set is logged and a rest starts automatically.
- [x] Start a countdown, then tap Stop → no prefill.
- [x] During a countdown the bar hides the rest quick-pick; a timed start replaced a running rest.

> **Checkpoint — slice A complete.** The phone-only timers can ship on their own (possible PR boundary).

---

## Phase 4: Watch app mirrors the running timer

### Changes

#### 1. Watch target and scheme
**File**: `project.yml` · **Action**: modify

```yaml
  TrainMe:
    # …existing…
    dependencies:
      - target: TrainMeWatch
  TrainMeWatch:
    type: application
    platform: watchOS
    deploymentTarget: "26.0"
    sources: [Watch, Shared]
    settings:
      base:
        DEVELOPMENT_TEAM: ZD9JLCY7TF
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: com.madacgrav.trainme.watchkitapp
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: TrainMe
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.madacgrav.trainme
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: NO
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
schemes:
  # TrainMe scheme unchanged
  TrainMeWatch:
    build:
      targets:
        TrainMeWatch: all
```

After `xcodegen generate`, check:

```bash
grep -n "Embed Watch Content\|com.apple.product-type.application\|SDKROOT = watchos" TrainMe.xcodeproj/project.pbxproj
```

Expect an "Embed Watch Content" copy phase with `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`. If it is missing, change the dependency to:

```yaml
      - target: TrainMeWatch
        embed: true
        copy:
          destination: productsDirectory
          subpath: "$(CONTENTS_FOLDER_PATH)/Watch"
```

Do not use `supportedDestinations` (XcodeGen PR 1470 drops the embed phase). If the iOS test build then fails with a missing watchOS platform, run `xcodebuild -downloadPlatform watchOS` locally and add the same as a CI step before "Test".

#### 2. Shared snapshot and codec
**File**: `SH/Sync/TimerSnapshot.swift` · **Action**: create

```swift
import Foundation

/// Phone → watch state. The newest `sentAt` wins on the watch.
struct TimerSnapshot: Codable, Sendable, Equatable {
    var timer: ActiveTimer?
    var upNext: UpNext?          // Phase 5 fills this; nil until then
    var defaultRest: Int
    var quickPicks: [Int]
    var sentAt: Date
}
```

In Phase 4, also create `SH/Sync/UpNext.swift` with only the struct (Phase 5 adds derivation):

```swift
struct UpNext: Codable, Sendable, Equatable {
    let plannedEntryId: UUID
    let instanceId: UUID
    let exerciseName: String
    let seconds: Int
}
```

**File**: `SH/Sync/SyncCodec.swift` · **Action**: create

```swift
import Foundation

enum SyncCodec {
    static let payloadKey = "payload"
    static let kindKey = "kind"   // "snapshot" | "command"

    static func encode<T: Encodable>(_ value: T, kind: String) throws -> [String: Any] {
        [payloadKey: try JSONEncoder().encode(value), kindKey: kind]
    }

    static func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any], kind: String) -> T? {
        guard dict[kindKey] as? String == kind, let data = dict[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
```

#### 3. Phone sync service
**File**: `S/Services/WatchSyncService.swift` · **Action**: create

```swift
import Foundation
import WatchConnectivity

protocol WatchSyncing: Sendable {
    func activate() async
    func send(_ snapshot: TimerSnapshot) async
}

struct NoopWatchSync: WatchSyncing {
    func activate() async {}
    func send(_ snapshot: TimerSnapshot) async {}
}

/// `WCSession` is documented thread-safe; this class holds no mutable state of its own.
final class WCSessionWatchSync: NSObject, WatchSyncing, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() async {
        session?.delegate = self
        session?.activate()
    }

    func send(_ snapshot: TimerSnapshot) async {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let payload = try? SyncCodec.encode(snapshot, kind: "snapshot") else { return }
        do { try session.updateApplicationContext(payload) } catch {
            Log.sync.error("context update failed: \(error.localizedDescription)")
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Log.sync.debug("sendMessage failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error { Log.sync.error("activation failed: \(error.localizedDescription)") }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
```

**File**: `S/Support/Log.swift` · **Action**: modify. Add `static let sync = Logger(subsystem: subsystem, category: "sync")`.

#### 4. Store pushes snapshots
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: modify
- Add an init parameter `sync: any WatchSyncing = NoopWatchSync()`, stored `@ObservationIgnored`.
- Add `private(set) var upNext: UpNext?` (set in Phase 5).
- Add `func activateSync() async { await sync.activate(); pushSnapshot() }`.
- Add `private var defaultRest: Int { let v = defaults.integer(forKey: TimerSettings.defaultRestKey); return v > 0 ? v : TimerMath.defaultRest }`.
- Add:
  ```swift
  func snapshot() -> TimerSnapshot {
      TimerSnapshot(timer: active, upNext: upNext, defaultRest: defaultRest, quickPicks: TimerMath.quickPicks, sentAt: now())
  }
  private func pushSnapshot() {
      let snap = snapshot()
      enqueue { [sync] in await sync.send(snap) }
  }
  ```
- Call `pushSnapshot()` at the end of `set(_:)`.

**File**: `S/TrainMeApp.swift` · **Action**: modify
- `@State private var timers = TimerStore(sync: WCSessionWatchSync())`.
- `.task { await timers.activateSync() }` on the WindowGroup content.

#### 5. Watch app
**File**: `W/TrainMeWatchApp.swift` · **Action**: create

```swift
import SwiftUI

@main
struct TrainMeWatchApp: App {
    @State private var model = WatchTimerModel()

    var body: some Scene {
        WindowGroup {
            TimerScreen()
                .environment(model)
                .task { model.activate() }
        }
    }
}
```

**File**: `W/PhoneLink.swift` · **Action**: create. This is the watch-side `WCSessionDelegate`, `final class … @unchecked Sendable`.
- `var onSnapshot: (@Sendable (TimerSnapshot) -> Void)?`, set before `activate()`.
- `activate()` sets the delegate and calls `WCSession.default.activate()`.
- `nonisolated` callbacks:
  - `activationDidCompleteWith` decodes `session.receivedApplicationContext`.
  - `didReceiveApplicationContext` and `didReceiveMessage` decode with `SyncCodec.decode(TimerSnapshot.self, from:kind: "snapshot")`, then call `onSnapshot?(snap)`.

**File**: `W/WatchTimerModel.swift` · **Action**: create

```swift
import Foundation
import Observation

@MainActor
@Observable
final class WatchTimerModel {
    private(set) var snapshot: TimerSnapshot?
    @ObservationIgnored private let link = PhoneLink()

    func activate() {
        link.onSnapshot = { [weak self] snap in Task { @MainActor in self?.apply(snap) } }
        link.activate()
    }

    /// Newest wins, so a late application context can't roll back a newer message.
    func apply(_ snap: TimerSnapshot) {
        if let current = snapshot, current.sentAt > snap.sentAt { return }
        snapshot = snap
    }
}
```

**File**: `W/TimerScreen.swift` · **Action**: create
- If `snapshot?.timer` is `t`: show it inside `TimelineView(.explicit([t.endAt]))`, but only while `context.date < t.endAt`:
  - Title "Rest" / "Timed set".
  - `ProgressView(timerInterval: t.startedAt...t.endAt, countsDown: true).progressViewStyle(.circular)`.
  - `Text(timerInterval: t.startedAt...t.endAt, countsDown: true).font(.title2.monospacedDigit())`.
- Otherwise show "No timer running" with secondary text "Start one from TrainMe on iPhone".
- Add a `#Preview` with a model that applies a fixture snapshot.

#### 6. CI
**File**: `.github/workflows/ci.yml` · **Action**: modify. Add after "Test":

```yaml
      - name: Build watch app
        run: |
          xcodebuild -scheme TrainMeWatch \
            -destination 'generic/platform=watchOS Simulator' \
            CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
            build
```

#### 7. Tests
**File**: `T/SyncCodecTests.swift` · **Action**: create
- `snapshotRoundTrips` (with a timer and a nil timer).
- `wrongKindReturnsNil`.
- `missingPayloadReturnsNil`.

**File**: `T/TimerStoreSyncTests.swift` · **Action**: create
- `actor FakeWatchSync: WatchSyncing` records `sent: [TimerSnapshot]`.
- `startSendsSnapshotWithTimer` (after `flush()`).
- `skipSendsSnapshotWithNilTimer`.
- `snapshotCarriesDefaultRestFromDefaults`: set 60 in the suite → `defaultRest == 60`.
- `activateSyncSendsInitialSnapshot`.

### Verification
#### Automated
- [x] Phase test command passes; `@Test` count ≥ 191.
- [x] `xcodebuild -scheme TrainMeWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3` → `BUILD SUCCEEDED`.
- [x] The pbxproj grep above shows the watch embed phase.

#### Manual (madphone + paired watch)
- [ ] Do a device build and install. TrainMe appears on the watch (install it from the Watch app if needed).
- [ ] Start a rest on the phone → the watch shows the same countdown within about 1 s, with the watch app open.
- [ ] Skip on the phone → the watch shows "No timer running".
- [ ] Open the watch app after starting a rest while it was closed → it shows the countdown (application context).

---

## Phase 5: Start and control timers from the watch

### Changes

#### 1. Commands
**File**: `SH/Sync/TimerCommand.swift` · **Action**: create

```swift
import Foundation

/// Watch → phone. The watch builds timers itself with `TimerMath`, so this works
/// the same whether delivered live (`sendMessage`) or queued (`transferUserInfo`).
enum TimerCommand: Codable, Sendable, Equatable {
    case adopt(ActiveTimer)       // start / extend / up-next
    case skip(timerId: UUID)
}
```

#### 2. Up next derivation
**File**: `S/Features/Session/UpNext+Derive.swift` · **Action**: create

```swift
import Foundation

/// First planned entry (instance order, then entry order) that still has sets to
/// log and tracks duration, with a positive target (or previous) duration.
func deriveUpNext(
    instances: [WorkoutInstanceDTO],
    recorded: [UUID: [SetRecordDTO]],
    exercises: [UUID: ExerciseDTO],
    previous: [UUID: SetRecordDTO]
) -> UpNext? {
    for instance in instances {
        for entry in instance.plannedEntries.sorted(by: { $0.order < $1.order }) {
            guard let exercise = exercises[entry.exerciseId] else { continue }
            let logged = recorded[instance.id, default: []].filter { $0.exerciseId == entry.exerciseId }.count
            guard logged < max(entry.targetSets ?? 1, 1) else { continue }
            guard exercise.metrics.contains(.duration) else { return nil }   // next exercise isn't timed
            let seconds = entry.targetDuration ?? previous[entry.exerciseId]?.duration ?? 0
            return seconds > 0
                ? UpNext(plannedEntryId: entry.id, instanceId: instance.id, exerciseName: exercise.name, seconds: seconds)
                : nil
        }
    }
    return nil
}
```

Up next is only offered when the *next* unfinished entry is timed. That matches "the next thing to do".

**File**: `S/Features/Session/SessionRunViewModel.swift` · **Action**: modify. Add one computed property, with no init change:

```swift
    /// Offered to the watch as a one-tap timed-set countdown.
    var upNext: UpNext? {
        guard session.status == .scheduled else { return nil }
        return deriveUpNext(instances: session.instances, recorded: recordedSets, exercises: exercises, previous: previousSets)
    }
```

**File**: `S/Features/Session/SessionRunView.swift` · **Action**: modify

```swift
        .onChange(of: viewModel.upNext, initial: true) { _, next in timers.setUpNext(next) }
        .onDisappear { timers.setUpNext(nil) }
```

#### 3. Store applies commands
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: modify

```swift
    func setUpNext(_ next: UpNext?) {
        guard next != upNext else { return }
        upNext = next
        pushSnapshot()
    }

    /// Rejected or stale commands still push a snapshot so the watch converges.
    func apply(_ command: TimerCommand) {
        switch command {
        case .adopt(let timer):
            if TimerMath.isComplete(timer, now: now()) || !start(timer) { pushSnapshot() }
        case .skip(let id):
            if active?.id == id { skip() } else { pushSnapshot() }
        }
    }

    func listen() async {
        for await command in sync.commands { apply(command) }
    }
```

`WatchSyncing` gains `var commands: AsyncStream<TimerCommand> { get }`:
- `NoopWatchSync` returns `AsyncStream { $0.finish() }`.
- `WCSessionWatchSync` gets `let commands: AsyncStream<TimerCommand>` and a private `let continuation`, made with `AsyncStream.makeStream()` in `override init()`.
- Add `nonisolated` `didReceiveMessage` and `didReceiveUserInfo`, which decode `SyncCodec.decode(TimerCommand.self, from:kind: "command")` and `yield`.

`TrainMeApp` `.task`: `await timers.activateSync(); await timers.listen()`.

#### 4. Watch controls
**File**: `W/PhoneLink.swift` · **Action**: modify

```swift
    func send(_ command: TimerCommand) {
        guard let payload = try? SyncCodec.encode(command, kind: "command") else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }
```

**File**: `W/WatchTimerModel.swift` · **Action**: modify. The changes apply optimistically to the local snapshot (`sentAt = .now`), then send:

```swift
    func startRest(seconds: Int) { adopt(TimerMath.make(kind: .rest, seconds: seconds, now: .now)) }

    func startUpNext() {
        guard let next = snapshot?.upNext else { return }
        adopt(TimerMath.make(kind: .timedSet(plannedEntryId: next.plannedEntryId, instanceId: next.instanceId),
                             seconds: next.seconds, now: .now))
    }

    func extend() {
        guard let t = snapshot?.timer else { return }
        adopt(TimerMath.extended(t, by: TimerMath.extendStep, now: .now))
    }

    func skip() {
        guard let t = snapshot?.timer else { return }
        updateLocal(timer: nil)
        link.send(.skip(timerId: t.id))
    }

    private func adopt(_ timer: ActiveTimer) {
        guard TimerMath.canReplace(snapshot?.timer, with: timer, now: .now) else { return }
        updateLocal(timer: timer)
        link.send(.adopt(timer))
    }

    private func updateLocal(timer: ActiveTimer?) {
        var snap = snapshot ?? TimerSnapshot(timer: nil, upNext: nil, defaultRest: TimerMath.defaultRest,
                                             quickPicks: TimerMath.quickPicks, sentAt: .now)
        snap.timer = timer
        snap.sentAt = .now
        snapshot = snap
    }
```

**File**: `W/QuickStartView.swift` · **Action**: create. This is the idle state (replaces the "No timer running" body in `TimerScreen`):
- If `upNext` exists: a prominent `Button("\(name) · \(seconds) s", systemImage: "timer") { model.startUpNext() }`.
- `ForEach(quickPicks)` buttons "Rest \(n) s"; the one equal to `defaultRest` is `.borderedProminent`.

**File**: `W/TimerScreen.swift` · **Action**: modify. The running state gets `Button("+15 s") { model.extend() }` and `Button("Skip", role: .destructive) { model.skip() }`. The idle state renders `QuickStartView()`.

#### 5. Tests
**File**: `T/UpNextTests.swift` · **Action**: create
- `firstUnfinishedTimedEntryWins`.
- `skipsFinishedEntries` (logged == targetSets).
- `nilWhenNextEntryNotTimed`.
- `usesPreviousDurationWithoutTarget`.
- `nilWhenNoDuration`.
- `respectsEntryOrderNotArrayOrder`.
- `viewModelUpNextNilWhenNotScheduled` (completed session).

**File**: `T/TimerCommandTests.swift` · **Action**: create (`@MainActor`, test clock, fakes)
- `adoptStartsTimerWithWatchId`.
- `adoptExtendSameIdReplaces`.
- `adoptStaleTimerIgnoredButSnapshotSent`.
- `adoptRestDuringTimedSetRejectedAndSnapshotSent`.
- `skipMatchingIdClears`.
- `skipOtherIdIgnored`.
- `commandRoundTripsThroughCodec`.
- `setUpNextPushesOnlyOnChange`.

### Verification
#### Automated
- [x] Phase test command passes; `@Test` count ≥ 206.
- [x] Watch build command → `BUILD SUCCEEDED`.

#### Manual (madphone + watch)
- [ ] Phone run screen open, watch app idle: tap "Rest 60 s" on the watch → the phone bar shows the rest. +15 on the watch → the phone shows the new end. Skip on the watch → both clear.
- [ ] A session whose next unfinished entry is Plank → the watch shows "Plank · 60 s". Start it → the phone bar shows "Timed set" → at zero the phone's Plank draft reads 60.
- [ ] Phone in airplane mode / out of range: starting a rest on the watch runs locally. Back in range → the phone adopts it.
- [ ] Leave the run screen → the watch's Up next button disappears.

---

## Phase 6: Wrist cue at zero and duplicate guard

### Changes

#### 1. Cue ownership
**File**: `S/Services/WatchSyncService.swift` · **Action**: modify

```swift
struct CueState: Sendable, Equatable {
    var watchAppInstalled: Bool
    var paired: Bool
    var reachable: Bool
}

/// The watch owns the zero cue only when it can certainly hear about the timer now.
func phoneOwnsCue(_ cue: CueState) -> Bool {
    !(cue.watchAppInstalled && cue.paired && cue.reachable)
}
```

- `WatchSyncing` gains `func cueState() async -> CueState`.
- `NoopWatchSync` returns all `false`, so the phone owns the cue.
- `WCSessionWatchSync` reads `isWatchAppInstalled`, `isPaired` and `isReachable`, or returns all false when unactivated.

#### 2. Phone skips its notification when the watch owns the cue
**File**: `S/Features/Timer/TimerStore.swift` · **Action**: modify. In `set(_:)`:

```swift
        enqueue { [notifier, sync] in
            await notifier.cancelAll()
            if let timer, phoneOwnsCue(await sync.cueState()) { await notifier.schedule(timer) }
        }
```

#### 3. Watch notification and haptic
**File**: `W/WatchNotifier.swift` · **Action**: create
- `struct WatchNotifier: Sendable`.
- `requestAuthorization()` asks for `[.alert, .sound]`.
- `reschedule(_ timer: ActiveTimer?)` cancels pending `timer-`-prefixed requests. When a timer is present and its interval is ≥ 1, it adds a `UNTimeIntervalNotificationTrigger` request with id `"timer-" + id.uuidString` and the same titles as the phone ("Rest over" / "Timed set done"). Duplicate those two strings here: `S/` is not compiled into the watch.

**File**: `W/WatchTimerModel.swift` · **Action**: modify
- `activate()` also calls `Task { await notifier.requestAuthorization() }`.
- At the end of `apply(_:)` and `updateLocal(timer:)`, call `Task { await notifier.reschedule(snapshot?.timer) }` and `armHaptic()`.
- `armHaptic()`:
  ```swift
  hapticTask?.cancel()
  guard let t = snapshot?.timer else { return }
  hapticTask = Task {
      try? await Task.sleep(for: .seconds(max(0, t.endAt.timeIntervalSinceNow)))
      guard !Task.isCancelled else { return }
      WKInterfaceDevice.current().play(.stop)
  }
  ```
  `hapticTask` is `@ObservationIgnored`. Add `import WatchKit`.
- A foreground notification is not presented without a delegate, so the open watch app gets the haptic only, and wrist-down gets the notification only.

#### 4. Tests
**File**: `T/CueOwnershipTests.swift` · **Action**: create
- `phoneOwnsCue` truth table: 8 combinations. Only all-true → false.

**File**: `T/TimerStoreTests.swift` · **Action**: modify
- `FakeWatchSync` gains a settable `cue`.
- `watchOwnedCueSkipsPhoneNotification`: all true → `scheduled` is empty and `cancelCount == 1`.
- `unreachableWatchPhoneNotifies`.

### Verification
#### Automated
- [x] Phase test command passes; `@Test` count 211 (the cue truth table is one parameterized test covering all 8 cases, not 8 tests).
- [x] Watch build command → `BUILD SUCCEEDED`.

#### Manual (madphone + watch)
- [ ] Watch app open, start a 30 s rest from the phone: at zero the watch taps once and the phone shows no notification.
- [ ] Start a 60 s rest from the watch, then lower the wrist: at zero exactly one wrist tap and notification ("Rest over").
- [ ] Watch app closed / out of range, start a rest on the phone and lock it: the phone notification fires (and mirrors to the watch if worn).
- [ ] Skip a rest on either device → neither device notifies later.

---

## Pending device checks (noted 2026-11-01)

The owner will check these later on madphone and the paired watch. They are **not** done.

**Device build to use:** local-only branch `local/device-nasm-gh38` (worktree `~/wt/trainme/local-device-nasm-gh38`). It is the NASM branch with GH-38 merged in (`d12c3ab`, all six phases), and is installed on madphone. Never push it. madphone's store is SchemaV3 (NASM), so a build from this branch alone (SchemaV2) shows "TrainMe couldn't open its data store". Never tap "Start fresh" there. To pick up later GH-38 phases, merge GH-38 into that branch again before building.

- [ ] Phase 1: the haptic plays at zero with the app open.
- [ ] Phase 2: with the phone locked and the watch worn, "Rest over" mirrors to the watch with a wrist tap.
- [ ] Phase 4: TrainMe installs on the watch with the phone app.
- [ ] Phase 4: starting a rest on the phone shows the same countdown on the watch within about 1 s.
- [ ] Phase 4: Skip on the phone clears the watch.
- [ ] Phase 4: opening the watch app after a rest started shows the countdown (application context).
- [ ] Phase 6: all four manual checks under Phase 6 (single wrist tap with app open, single tap wrist-down, phone fallback when watch is away, no cue after skip).
- [ ] Phase 5: all four manual checks under Phase 5 (watch start/extend/skip, Up next prefill, offline adopt, Up next clears on leaving).
