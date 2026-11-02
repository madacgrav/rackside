# Structure Outline — GH-38 Quick timers (with Apple Watch)

## Approach
An end-date-based `TimerStore` is owned by `TrainMeApp` above `LockGateView` and injected via the environment. The phone gets rest timers, persistence/notifications and timed-set countdowns first (Phases 1–3, shippable alone as slice A). A companion watch app then mirrors the timer (Phase 4), drives it (Phase 5), and owns the wrist cue (Phase 6). Shared value types live in a top-level `Shared/` folder compiled into both targets.

Test command for every phase:
`xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' test`

---

## Phase 1: Rest timer on the phone (in memory)
Logging a set starts a rest countdown with the Settings default. A timer bar on the run screen shows the remaining time with quick picks, +15 s and Skip. A haptic plays at zero while the app is foreground.

**Files**: `project.yml` (add `Shared` to `TrainMe.sources`), `Shared/Timer/ActiveTimer.swift`, `Shared/Timer/TimerMath.swift`, `Sources/Features/Timer/TimerStore.swift`, `Sources/Features/Timer/TimerBar.swift`, `Sources/TrainMeApp.swift`, `Sources/Features/Session/SessionRunView.swift`, `Sources/Features/Session/SessionRunViewModel.swift`, `Sources/Features/Settings/SettingsView.swift`, `Tests/TimerStoreTests.swift`, `Tests/TimerMathTests.swift`
**Key changes**:
- `struct ActiveTimer: Codable, Sendable, Equatable { id: UUID; kind: TimerKind; startedAt: Date; endAt: Date }`
- `enum TimerKind: Codable, Sendable, Equatable { case rest; case timedSet(plannedEntryId: UUID, instanceId: UUID) }`
- `enum TimerMath { static func remaining(_:now:) -> TimeInterval; static func isComplete(_:now:) -> Bool; static func extended(_:by:now:) -> ActiveTimer }`
- `@MainActor @Observable final class TimerStore { private(set) var active: ActiveTimer?; private(set) var completionTick: Int; init(now: @escaping @Sendable () -> Date = Date.init); func startRest(seconds: Int); func extend(by: Int); func skip(); func refresh() }`. One timer at a time: `startRest` is a no-op while a `.timedSet` runs.
- `TrainMeApp`: `@State private var timers = TimerStore()` → `.environment(timers)` on the `WindowGroup` content (wrapping `LockGateView`).
- `SessionRunViewModel.init(..., onSetLogged: @MainActor () -> Void = {})`, called beside `lastLoggedSetId = UUID()` (`SessionRunViewModel.swift:199`). `SessionRunView` wires it to `timers.startRest(seconds: defaultRestSeconds)`.
- `@AppStorage("defaultRestSeconds") = 90` with a picker in `SettingsView`. Quick picks `[60, 90, 120]` are a constant in `Shared/Timer/TimerMath.swift`.
- `TimerBar` uses `Text(timerInterval:countsDown:)`, `.sensoryFeedback(.warning, trigger: store.completionTick)`.

**Verify**: tests pass (start/extend/skip/complete via injected clock; rest is rejected during a timed set; `onSetLogged` fires only on a successful log). Manual (simulator): log a set → the bar counts down from 90; +15 and Skip work; the haptic trigger fires at zero.

---

## Phase 2: Timers survive background, lock and relaunch
The store persists the active timer and restores it at launch. A local notification fires at zero when the app isn't in front.

**Files**: `Sources/Features/Timer/TimerStore.swift`, `Sources/Services/TimerNotificationService.swift`, `Sources/TrainMeApp.swift`, `Sources/RootView.swift` (or app-level `scenePhase` hook calling `timers.refresh()`), `Tests/TimerStoreTests.swift`, `Tests/TimerNotificationTests.swift`
**Key changes**:
- `TimerStore.init(defaults: UserDefaults = .standard, notifier: any TimerNotifying = LocalTimerNotifier(), now: ...)`. The key is `"activeTimer"` (JSON). Restore drops a timer whose `endAt` is more than 60 s past.
- `protocol TimerNotifying: Sendable { func schedule(_ timer: ActiveTimer, title: String) async; func cancelAll() async }`. Ids are `timer-<UUID>`. `cancelAll` removes only `timer-`-prefixed requests (mirrors `NotificationService.swift:87-88`).
- `func timerNotificationIdentifier(_ id: UUID) -> String` as a pure free function.
- Every mutation (`start`/`extend`/`skip`/replace) persists, then cancels and reschedules.
- `refresh()` on `.active` recomputes completion from `endAt` and runs the single `Task.sleep(until:)` completion watcher while active.

**Verify**: tests pass (round-trip persistence with a `UserDefaults` suite; stale timers dropped; `FakeTimerNotifier` records schedule/cancel; `sess-` ids untouched). Manual (device, madphone): start a rest, lock the phone → the notification arrives at zero; the app lock + unlock keeps the bar; killing the app mid-rest → relaunch shows the remaining time.

---

## Phase 3: Timed-set countdown with prefill
The draft row of a duration exercise gets a Start button that counts down from the draft/target seconds. At zero the draft's duration is prefilled and nothing is logged.

**Files**: `Sources/Features/Session/SetTableView.swift`, `Sources/Features/Timer/TimerStore.swift`, `Sources/Features/Session/SessionRunView.swift`, `Tests/TimerStoreTests.swift`, `Tests/SetDraftPrefillTests.swift`
**Key changes**:
- `TimerStore.startTimedSet(plannedEntryId: UUID, instanceId: UUID, seconds: Int)` replaces any rest.
- `TimerStore.lastCompletion: TimerCompletion?` — `struct TimerCompletion: Equatable { timerId: UUID; kind: TimerKind; seconds: Int }`.
- `SetDraft.prefilled(duration: Int) -> SetDraft` (pure; sets duration only when the metric is tracked).
- `SetTableView`: a Start/Stop control in the draft row when `metricSet(.duration)`. `.onChange(of: timers.lastCompletion)` → if the kind matches this entry, `draft = draft.prefilled(...)`, `draftTouched = true`.
- Skip on a timed set records no completion. A completion with the screen closed is dropped (per design).

**Verify**: tests pass (completion emitted once with the right seconds; skip emits none; prefill is a no-op without `.duration`). Manual: Plank entry → Start → at zero the duration cell shows the target seconds; the checkmark logs it, and logging then auto-starts a rest.

> **Checkpoint — slice A complete.** Phone-only timers are usable and shippable on their own. The watch already buzzes via notification mirroring when the phone is locked.

---

## Phase 4: Watch app mirrors the running timer
A new companion watch app shows the phone's active timer (kind, ring, remaining time), synced over WatchConnectivity. It is read-only.

**Files**: `project.yml` (target `TrainMeWatch`, watchOS 26, bundle `com.madacgrav.trainme.watchkitapp`, sources `[Watch, Shared]`, embedded from `TrainMe`; scheme `TrainMeWatch`), `Watch/TrainMeWatchApp.swift`, `Watch/TimerScreen.swift`, `Watch/WatchTimerModel.swift`, `Watch/Info.plist`, `Shared/Sync/TimerSnapshot.swift`, `Shared/Sync/SyncCodec.swift`, `Sources/Services/WatchSyncService.swift`, `Sources/Features/Timer/TimerStore.swift`, `.github/workflows/ci.yml`, `Tests/SyncCodecTests.swift`, `Tests/TimerStoreSyncTests.swift`
**Key changes**:
- `struct TimerSnapshot: Codable, Sendable, Equatable { timer: ActiveTimer?; upNext: UpNext?; defaultRest: Int; quickPicks: [Int]; sentAt: Date }` (`upNext` stays nil until Phase 5).
- `enum SyncCodec { static func encode(_: TimerSnapshot) throws -> [String: Any]; static func decodeSnapshot(_: [String: Any]) throws -> TimerSnapshot }` using a single `"payload": Data` key.
- `protocol WatchSyncing: Sendable { func activate() async; func send(_ snapshot: TimerSnapshot) async; var commands: AsyncStream<TimerCommand> { get } }`. `WCSessionWatchSync` is the adapter (`nonisolated` delegate callbacks, `sendMessage` if reachable + `updateApplicationContext` always).
- `TimerStore` gains `sync: any WatchSyncing` and pushes a snapshot after every mutation.
- Watch: `@MainActor @Observable WatchTimerModel` holds the latest snapshot. `TimerScreen` renders `Text(timerInterval:)` + `ProgressView(timerInterval:)`.
- CI: add `xcodebuild -scheme TrainMeWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

**Verify**: iOS tests pass (codec round-trip; store sends a snapshot on each mutation via `FakeWatchSync`); the watch scheme builds in CI. Manual (madphone + paired watch): start a rest on the phone → the watch shows the same countdown within about 1 s; Skip on the phone clears the watch.

---

## Phase 5: Start and control timers from the watch
The watch can start a rest from quick picks, +15 s, Skip, and start the phone-advertised **Up next** timed set.

**Files**: `Shared/Sync/TimerCommand.swift`, `Shared/Sync/UpNext.swift`, `Sources/Features/Session/UpNext+Derive.swift`, `Sources/Features/Session/SessionRunViewModel.swift`, `Sources/Features/Timer/TimerStore.swift`, `Sources/Services/WatchSyncService.swift`, `Watch/TimerScreen.swift`, `Watch/QuickStartView.swift`, `Watch/WatchTimerModel.swift`, `Tests/UpNextTests.swift`, `Tests/TimerCommandTests.swift`
**Key changes**:
- `enum TimerCommand: Codable, Sendable { case startRest(seconds: Int); case startUpNext; case extend(seconds: Int); case skip }`
- `struct UpNext: Codable, Sendable, Equatable { plannedEntryId: UUID; instanceId: UUID; exerciseName: String; seconds: Int }`
- `func deriveUpNext(instances: [WorkoutInstanceDTO], recorded: [UUID: [SetRecordDTO]], exercises: [UUID: ExerciseDTO]) -> UpNext?` (pure; first entry by `order` with remaining sets that tracks `.duration`).
- `SessionRunViewModel` publishes `timers.setUpNext(_:)` after `load()` and each record/delete. `SessionRunView` `.onDisappear` → `timers.setUpNext(nil)`.
- `TimerStore.apply(_ command: TimerCommand)` consumes `sync.commands`.
- Watch sends a command via `sendMessage`, falling back to `transferUserInfo`. When unreachable it starts the timer locally and the phone adopts it from the next context.

**Verify**: tests pass (`deriveUpNext` order/remaining/metric cases; `apply` maps each command; unreachable-adopt merge rule). Manual: from the watch start 60 s rest → the phone bar appears; Up next shows "Plank 45s" → start → at zero the phone draft is prefilled.

---

## Phase 6: Wrist cue at zero and duplicate guard
The watch plays a haptic in the foreground and schedules its own local notification for wrist-down. The phone stops notifying when the watch owns the cue.

**Files**: `Watch/WatchTimerModel.swift`, `Watch/WatchNotifier.swift`, `Sources/Features/Timer/TimerStore.swift`, `Sources/Services/WatchSyncService.swift`, `Tests/TimerStoreTests.swift`, `Tests/CueOwnershipTests.swift`
**Key changes**:
- `func phoneOwnsCue(watchAppInstalled: Bool, paired: Bool, reachableAtStart: Bool) -> Bool` (pure; the phone notifies unless installed && paired && reachable).
- `WatchSyncing` gains `var cueState: CueState { get async }` (`installed`, `paired`, `reachable`).
- Watch: on each snapshot it cancels and reschedules a `timer-` notification at `endAt`. In the foreground at zero it calls `WKInterfaceDevice.current().play(.stop)`.

**Verify**: tests pass (cue ownership truth table; store skips phone scheduling when the watch owns it). Manual: phone in pocket, wrist down → exactly one buzz on the watch at zero; watch off-wrist/out of range → the phone notification still arrives.

---

## Testing Checkpoints
| After | True statements |
|---|---|
| P1 | Logging a set starts a 90 s rest bar; quick picks/+15/Skip work; foreground haptic at zero; Settings default respected. |
| P2 | The timer survives lock, background and kill; a phone notification fires at zero (`timer-` ids) without touching `sess-` reminders. |
| P3 | Duration exercises have a Start countdown that prefills the draft; no auto-log; slice A shippable. |
| P4 | Watch target builds in CI; the watch mirrors the phone timer read-only. |
| P5 | The watch starts rest / up-next timers and +15/Skip; the phone adopts watch-started timers. |
| P6 | Exactly one cue at zero, owned by the watch when it is installed, paired and reachable; otherwise by the phone. |
