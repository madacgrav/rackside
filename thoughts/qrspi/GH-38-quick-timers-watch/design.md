# Design Discussion — GH-38 Quick timers (with Apple Watch)

Inputs: `task.md`, `research.md` (codebase), `watch-research.md` (platform, partly unverified).
Owner decisions (2026-11-01): full watch app; app-level timer store; quick picks + default rest; rest auto-starts, timed countdown prefills.

## Current State
- **No timer primitives anywhere.** No `Timer`, `TimelineView`, background modes, or idle-timer handling in `Sources/` (research Q4). The duration field is a `MetricStepper` with `step: 15` (`SetTableView.swift:166-171`).
- **Duration is modeled end to end** as `Int` seconds: `WorkoutEntry.targetDuration` (`Workout.swift:29`) → frozen `PlannedEntry.targetDuration` (`Session.swift:91`) → draft seed (`SetDraft.swift:13`) → `SetRecord.duration` (`SetRecord.swift:12`). Duration applies when `exercise.metrics.contains(.duration)` (`Exercise.swift:13-21`). No rest/pace field exists (research Q2).
- **Run-screen state is temporary.** Drafts are `@State` in each `SetTableView` (`SetTableView.swift:14-18`). The view model is `@State` on a pushed `SessionRunView` (`SessionRunView.swift:4`). No `onDisappear` (`:234`).
- **The lock tears down the UI.** `LockGateView` renders `if lock.isUnlocked { content() } else { lockScreen }` (`LockGateView.swift:11-17`) and locks on `.background` (`:21-22`). Anything owned below it dies on every background.
- **Cues:** one `.sensoryFeedback(.success, trigger: lastLoggedSetId)` (`SessionRunView.swift:125`, set at `SessionRunViewModel.swift:199`). Notifications are calendar-triggered session reminders behind `NotificationScheduling` (`NotificationService.swift:61-67`). `reschedule` only clears `sess-`-prefixed requests (`:87-88`). Permission is already requested at `RootView.swift:108`. No `UNUserNotificationCenterDelegate`, so there is no foreground presentation.
- **Single target.** `project.yml:11-33` defines `TrainMe` + `TrainMeTests` only. Entitlements are empty (`TrainMe.entitlements:4`). There is no app group. CI builds/tests on an iPhone 17 simulator with signing off (`ci.yml:22-27`).

## Desired End State
On the **phone** session run screen:
1. Logging a set auto-starts a rest countdown (default from Settings, e.g. 90 s). A compact timer bar shows the remaining time with quick picks (60/90/120), +15 s, and Skip.
2. For a duration exercise, the draft row offers **Start** (a countdown from `targetDuration`, or the current draft value). At zero, the draft's duration is prefilled with the counted seconds. Logging stays a tap on the checkmark.
3. At zero: an in-app haptic if foreground, plus a local notification so a locked phone (and a worn watch via mirroring) buzzes.
4. Timers survive switching entries, backgrounding, the app lock and process death (the end date is persisted and restored).

On the **watch** (companion app):
5. It shows the running timer (kind, remaining time, ring) with Skip / +15 s.
6. It can start a rest timer from quick picks, and can start the **Up next** timed-set countdown the phone advertises.
7. A haptic at zero on the wrist. Phone and watch converge on the same end date within about 1 s when reachable.

**Verification:** unit tests for the timer store (start/extend/skip/complete/restore with an injected clock + `UserDefaults` suite), the "up next" derivation, prefill, and message encoding. CI builds both targets. A manual device pass on madphone + paired watch covers backgrounding, the lock, wrist-down haptic, and watch-started timers.

## Patterns to Follow
- **`@MainActor @Observable final class` with constructor-injected protocols** for the store and session glue (`SessionRunViewModel.swift:4-73`; `ReminderCoordinator.swift:7-24`).
- **`Sendable` service protocol + concrete impl** (often an `actor`) for anything OS-facing: notifications (`NotificationService.swift:61-69`), calendar (`CalendarService.swift:55, 74`). Use this for timer notifications and WatchConnectivity.
- **Pure free functions for decision logic**, tested without the OS (`selectAlerts`, `NotificationService.swift:15-49`; tests `NotificationSchedulingTests.swift:9-48`). Use this for "up next" and timer math.
- **Injected `UserDefaults`** with suite isolation in tests (`ScheduleViewModel.swift:12, 40-50`; `ScheduleViewModelTests.swift:49`). `@AppStorage` for simple settings (`SettingsView.swift:15`).
- **Notification identifier prefixes** scoped per feature (`sess-`, `NotificationService.swift:53`) so features don't cancel each other.
- **DTOs across boundaries, never models** (repos return DTOs; research Q6). Watch messages carry small value structs, not SwiftData objects.
- **Swift Testing + fakes** (`ReminderCoordinatorTests.swift:6-19`). Previews via `PreviewFixtures` (`PreviewFixtures.swift:111-156`).
- **Do NOT follow:** owning long-lived state in view `@State` below `LockGateView` (`SessionRunView.swift:4`; `SetTableView.swift:14-18`). It is fine for drafts but wrong for timers. Do not use `scenePhase` `.inactive` as a background signal (Face ID drops to `.inactive`, `LockGateView.swift:3-4`).

## Design Decisions
1. **Watch delivery: companion watchOS app (single target, embedded in the iOS app)** — owner choice. It enables starting timers from the wrist. No standalone mode: the phone is the source of truth for session context.
2. **Timer state: `TimerStore` at app level** — `@MainActor @Observable`, created in `TrainMeApp` *above* `LockGateView` and passed through the environment. State is one `ActiveTimer?` `{ id, kind (.rest | .timedSet(plannedEntryId, instanceId)), startedAt, endAt, pausedRemaining? }`. It is end-date based, with no ticking state. The UI uses `Text(timerInterval:)` / `TimelineView`. It is persisted as JSON in injected `UserDefaults` and restored at launch (dropped if `endAt` is long past).
3. **One timer at a time.** Starting a new one replaces the current one. A rest started while a timed countdown runs is rejected (the countdown wins). This keeps the watch UI and notification handling trivial.
4. **Rest config: quick picks + `@AppStorage("defaultRestSeconds")`** (default 90) in Settings. No schema, DTO or archive change. Per-entry rest is out of scope.
5. **Automation:** a successful `record(draft:)` starts a rest with the default (hook next to `lastLoggedSetId`, `SessionRunViewModel.swift:199`). The timed countdown is started explicitly and on completion publishes a `completedTimedSet(plannedEntryId, seconds)` event. The matching `SetTableView` sets `draft.duration` and `draftTouched = true`, and does **not** log.
6. **Cue at zero:**
   - Phone foreground: `.sensoryFeedback` on a store `completionTick`. The store runs a single main-actor `Task.sleep(until: endAt)` only while active.
   - Phone backgrounded/locked: a local notification scheduled at start via a new `TimerNotifying` protocol, id prefix `timer-`, cancelled on skip/replace/extend. It mirrors to the watch when the phone is locked.
   - Watch foreground: `WKInterfaceDevice.play(.stop)`.
   - Watch wrist-down: the watch app schedules its own local notification for timers it knows about. **Duplicate guard:** the phone skips its notification when `WCSession.isWatchAppInstalled && isPaired`, so only the watch notifies. No `WKExtendedRuntimeSession`/HealthKit in v1 (App Review + scope risk).
7. **Sync protocol: a `TimerSnapshot` value struct** `{ timer: ActiveTimer?, upNext: UpNext?, defaultRest, quickPicks, sentAt }`. The phone sends it via `sendMessage` when reachable, always mirrored with `updateApplicationContext`. The watch sends commands (`startRest(seconds)`, `startUpNext`, `extend(15)`, `skip`) via `sendMessage`, falling back to `transferUserInfo`. The phone applies them to `TimerStore` and replies with a fresh snapshot. If the phone isn't reachable, the watch runs the timer locally and the phone adopts it on the next context.
8. **"Up next" = a pure function** over planned entries + recorded sets: the first entry (by `order`) with remaining planned sets whose exercise tracks duration → `{ plannedEntryId, instanceId, exerciseName, seconds }`. `SessionRunViewModel` publishes it to `TimerStore` whenever sets change and clears it on leaving the session. This avoids inventing an "active exercise" concept that doesn't exist today (research Q1).
9. **Connectivity behind `WatchSyncing: Sendable`** with a `WCSessionDelegate` adapter (`nonisolated` callbacks, extract plain values, hop to `@MainActor`). The iOS app and tests use a fake. Shared value types (`ActiveTimer`, `TimerSnapshot`, commands, timer math) live in a `Shared/` source folder compiled into both targets. No framework target.
10. **Build:** add `TrainMeWatch` (watchOS 26, bundle `com.madacgrav.trainme.watchkitapp`, `WKCompanionAppBundleIdentifier`) to `project.yml`, embedded from `TrainMe`. CI keeps the iOS test action. The watch is verified with a separate `xcodebuild build` step for the watch scheme on a watchOS simulator.
11. **Delivery order (two PRs or two slices):** (a) phone timers + store + notification, which is useful alone and also buzzes the watch via mirroring; (b) watch target + sync. Slice (a) de-risks the core before the platform-uncertain work.

## What We're NOT Doing
- No Live Activity / Dynamic Island / widget extension, watch complications, or Controls.
- No AlarmKit, no `WKExtendedRuntimeSession`, no HealthKit / `HKWorkoutSession`.
- No per-entry rest field, schema migration, archive or DTO change. Timer history is not stored.
- No auto-logging of timed sets. No editing past sets from the watch. No session browsing on the watch.
- No standalone watch mode, app group, or shared SwiftData store.
- No `UNUserNotificationCenterDelegate` foreground presentation (the in-app haptic covers the foreground).
- No change to `LockGateView`'s teardown behaviour or to drafts being view-local.

## Open Risks
- **Wrist-down haptic reliability** with only a watch-scheduled local notification. If the watch app is suspended before scheduling (phone-started timer while unreachable), the cue may be lost. A device test is required. Fallback: extended runtime session (App Review fit unverified).
- **Duplicate guard correctness:** if `isWatchAppInstalled` is true but the watch is off-wrist or out of range, the phone sends no notification. Consider also notifying from the phone when `!isReachable` at start.
- **XcodeGen watch embedding** (product type, "Embed Watch Content", `supportedDestinations` caveat — XcodeGen PR 1470) and the **watchOS simulator runtime on `macos-26`** runners are unverified.
- **Swift 6 strict concurrency** with `WCSessionDelegate` and `[String: Any]` payloads. Prefer `Codable` → `Data` in a single key.
- **Restore semantics:** a timed countdown that completed while the app was dead should still prefill when its session is reopened, or be dropped? Proposed: drop it, and only rest/countdown display is restored.
- **Signing:** the watch target needs its own provisioning on device. Automatic signing with team `ZD9JLCY7TF` should handle it. Unverified until the first device install.
- `Task.sleep(until:)` drifting under suspension is a non-issue if completion is always recomputed from `endAt` on `.active`.
