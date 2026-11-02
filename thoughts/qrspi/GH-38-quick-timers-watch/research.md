# Research Findings

## Q1: Session run flow — presentation, view model ownership, in-progress set lifecycle

### Findings
**Presentation (push only, no sheet/fullScreenCover)**
- `ScheduleView.sessionLink(_:)` builds a `NavigationLink` whose destination is `SessionRunView(viewModel: SessionRunViewModel(...), workoutRepo: viewModel.workoutRepo)` (`Sources/Features/Schedule/ScheduleView.swift:98-114`). Used by day list (`:51-53`) and week list (`:141`). Client name/phone/injuries looked up by `session.clientId` (`:105-107`); `onStatusChanged: { await viewModel.load() }` (`:108`).
- `ClientDetailView.sessionLink(_:)` builds the same view for Upcoming (`Sources/Features/Clients/ClientDetailView.swift:31-33`) and Recent (`:40-42`) sessions, with `onStatusChanged: { await viewModel.reload() }` (`:106-115`). It omits `workoutRepo`, which defaults to nil (`Sources/Features/Session/SessionRunView.swift:7`).

**Creation and ownership**
- The view model is constructed inside the NavigationLink destination closure from the row's `SessionDTO` snapshot (`ScheduleView.swift:99-109`; `ClientDetailView.swift:105-115`) and held as `@State var viewModel` (`SessionRunView.swift:4`).
- `SessionRunViewModel` is `@MainActor @Observable final class` (`SessionRunViewModel.swift:4-6`); init stores repos, `calendar` defaulting to `EventKitCalendarService()`, session, client info, `notesDraft`, `onStatusChanged` (`:52-73`).
- `.task { await viewModel.load() }` (`SessionRunView.swift:234`). `load()` fills `exercises`, `recordedSets[instance.id]`, and `previousSets[exerciseId]` once per planned exercise via `lastSet` (`SessionRunViewModel.swift:75-90`; "captured once" comment `:26-28`).

**In-progress set (draft) lifecycle**
- Drafts live in `SetTableView`, not the view model: `@State draft: SetDraft`, `@State focusedMetric`, `@State draftTouched` (`SetTableView.swift:14-18`). One `SetTableView` per planned entry, all rendered in one `List` via `ForEach(instance.plannedEntries)` (`SessionRunView.swift:76-96`).
- Seeding: `initialDraft` uses `SetDraft(from: previous)` if a previous set exists, else `SetDraft(target: entry)` (`SetTableView.swift:32-34, 290-292`). `SetDraft(target:)` sets `duration = entry.targetDuration ?? 0` when metrics contain `.duration` (`SetDraft.swift:10-15`, line 13).
- Re-seed when async data arrives: `.onChange(of: exercise?.id)` / `.onChange(of: previous?.id)` → `resetDraftIfUntouched()` (`SetTableView.swift:59-60, 301-305`).
- Editing sets `draftTouched = true` (stepper bindings `:157-175`; Prev button `:96-101`). `focusedMetric` picks which stepper is visible (`:111, 152-179`).
- Rows: `plannedCount = max(targetSets ?? 1, logged.count + 1)` (`:40`); logged rows read-only (`:47-48`), row at `logged.count` is the editable draft + stepper strip (`:49-51`), later rows placeholders (`:52-53`).
- Logging: checkmark → `onLog(draft)` (`SetTableView.swift:123-125`) → `viewModel.record(draft:instanceId:exerciseId:)` (`SessionRunView.swift:89-91`). That filters by exercise metrics (fallback `[.weight, .reps]`) (`SessionRunViewModel.swift:189-197`), calls primitive `record` (computes `nextIndex`, builds `SetRecordDTO`, `rpe: nil`, `performedAt: .now`, `sessionRepo.recordSet`, reload `setsFor`) (`:158-185`), and sets `lastLoggedSetId = UUID()` on success (`:199`).
- After a log the same `SetTableView` `@State` persists; draft is not reset and carries its values to the next row.
- Delete: `onDelete` → `pendingDeleteSet` → confirmation → `viewModel.deleteSet` (`SetTableView.swift:84-85`; `SessionRunView.swift:92, 223-233`; `SessionRunViewModel.swift:202-214`).
- "Switching exercises": no active-exercise concept exists; each entry has an independent draft. No state transfers between entries.
- Dismissal: no `onDisappear`/teardown (`SessionRunView.swift:234` is the only lifecycle modifier). Unlogged drafts are discarded on pop. `dismiss()` is only called after session delete (`:175, 251, 261`).
- Progress: `progress`, `plannedSetCount`, `loggedSetCount` (`SessionRunViewModel.swift:32-44`) drive the top `ProgressView` (`SessionRunView.swift:116-124`).

**MetricStepper** (`Sources/Features/Components/MetricStepper.swift`)
- `label`, `@Binding value: Double`, `step`, `range = 0...10_000`, `fractionDigits = 1` (`:5-9`); −/+ clamp (`:13, 22`); centre `TextField` with `.decimalPad` (`:14-15`); optional binding adapters (`:37-51`). Used by `SetTableView` (`:155-177`) and `WorkoutBuilderView` (`:156`).

## Q2: Duration-type metrics across the stack

### Findings
**Models**
- `WorkoutEntry.targetDuration: Int?` (`Sources/Models/Workout.swift:29`), `PlannedEntry.targetDuration: Int?` (`Sources/Models/Session.swift:91`), `SetRecord.duration: Int?` (logged value, `Sources/Models/SetRecord.swift:12`). Frozen V1 copies at `SchemaV1.swift:95, 167, 190`.
- Units are implicit seconds: labels "Duration (sec)" (`SetTableView.swift:168`; `WorkoutBuilderView.swift:165`), "\(duration)s" formatting (`SessionRunView.swift:288`; `SetTableView.swift:267`).
- `Session` `startAt/endAt` and `duration: TimeInterval` in `SessionRepository.swift:45, 290-296` / `SessionEditView.swift:14, 91` are session length, unrelated to the set metric.

**Deciding duration applies**
- `MetricSet: OptionSet` — `.weight`, `.reps`, `.sets`, `.duration` (1<<3), `.distance` (`Sources/Models/Exercise.swift:13-21`), persisted as `Exercise.metricsRaw: Int` (`:39, 66`). `Unit` includes `min`/`sec` (`:8-10`).
- Seed exercises with duration: Plank, Treadmill/Outdoor Run, Rowing, Bike, Jump Rope, stretches, Foam Rolling (`Sources/Resources/seed_exercises.json:27-35`); mapped by `SeedImporter.swift:24-29`.
- User toggle "Duration" in `ExerciseEditView.swift:15, 30, 41, 65`.
- Consumers: `SetTableView.columns` (`:39, 251-258`), `SetDraft` (`:13, 20`), `SessionRunViewModel.record(draft:)` (`:196`). Unknown exercise falls back to `[.weight, .reps]` (no duration).

**Flow**
- Template: `OptionalStepper("Duration (sec)", range 5...7200, default 60, step 5)` (`WorkoutBuilderView.swift:165`) → `WorkoutEntryDTO.targetDuration` (`WorkoutDTO.swift:10, 30, 42`) → `WorkoutRepository.upsert`/`duplicate` (`WorkoutRepository.swift:29-34, 58`).
- Scheduling copies into frozen `PlannedEntry` (`SessionRepository.swift:398-413`) → `PlannedEntryDTO.targetDuration` (`SessionDTO.swift:10, 44, 56`).
- Run screen: target text (`SessionRunView.swift:288`), draft seed (`SetDraft.swift:13`), stepper `step: 15, fractionDigits: 0` via `Double`/`Int` bridging (`SetTableView.swift:166-171`), "Sec" column (`:236-237`).
- Log: `SetRecordDTO.duration` (`SetRecordDTO.swift:10, 27, 44`) → `recordSet` insert+save (`SessionRepository.swift:338-341`); read back via `setsFor` (`:352-359`) and `lastSet` (`:361-374`).
- Reporting: `ExerciseReportViewModel.swift:42-46`. Archive: DTOs embedded in `ArchiveV1.Envelope` (`ArchiveV1.swift:15-19`); export `DataArchive.swift:51`; import `:143, 157, 164, 171`. No duration-specific archive code.

**Rest / pacing**
- No rest, tempo, or pace property exists on `WorkoutEntry`, `PlannedEntry`, `SetRecord`, DTOs, archive, or UI. Per-entry fields: exerciseId, order, targetSets, targetReps, targetWeight, targetDuration (`SchemaV1.swift:88-108, 160-180`). `SetRecord`: setIndex, weight, reps, duration, distance, rpe, performedAt, createdAt, updatedAt (`:183-213`).
- `rpe` always written nil (`SessionRunViewModel.swift:169`); `performedAt = .now` is the only per-set timestamp (`:170`).
- `MetricSet.sets` exists but is not in `SetTableView`'s `Metric` enum (`SetTableView.swift:20-22`).

## Q3: Lifecycle (scenePhase) handling and surviving state

### Findings
- `TrainMeApp`: `.ready` → `LockGateView { RootView(container:) }`; `.failed` → `RecoveryView` (`Sources/TrainMeApp.swift:68-78`). No scenePhase observer, no app delegate. Launch work in `AppBootstrap.init`: remove import snapshot, `StoreBackup.backupIfVersionChanged`, open container (`:15-24`).
- scenePhase observers (only four):
  - `LockGateView`: `.background` → `lock.lock()`; `.active` → authenticate if locked; `.inactive` ignored (Face ID sheet) (`LockGateView.swift:3-4, 19-30`); `.task` authenticates at launch (`:18`).
  - `RootView`: `.active` → `reminders.refresh()` + `exportReminderIsDue()` (`RootView.swift:78-86`).
  - `SettingsView`: `.active` → `refreshPermissions()` (`SettingsView.swift:112-117, 167`).
- No `UIApplication` lifecycle notifications anywhere in `Sources/`.
- `AppLock` is `@MainActor @Observable`, `isUnlocked = false` initially, in-memory only (`AppLock.swift:5-8, 23-48`); owned as `@State` in `LockGateView` (`LockGateView.swift:7`).
- **The lock is a conditional, not an overlay**: `if lock.isUnlocked { content() } else { lockScreen }` (`LockGateView.swift:11-17`). On `.background` the whole `RootView` subtree — including a pushed `SessionRunView`, its view model, and all `SetTableView` drafts — is torn down. After unlock `RootView` is rebuilt with `selectedTab = 0` (`RootView.swift:10, 15-22`).
- Persisted state: no `@SceneStorage`. `@AppStorage`: `hasSeenBackupNotice`, `lastExportAt`, `wantsSelfClient` (`RootView.swift:7-9`), `defaultWeightUnit` (`SettingsView.swift:15`). `UserDefaults`: `scheduleMode` and `exportBannerDismissedAt` in `ScheduleViewModel` (injected `defaults`, `ScheduleViewModel.swift:12, 18, 30-31, 40-50, 86-98`); `lastRunSchemaVersion` in `StoreBackup` (`StoreBackup.swift:7-9, 21-47`).
- SwiftData store at `applicationSupportDirectory/default.store` (`TrainMeApp.swift:13`) holds logged sets. Not persisted: selected tab, navigation path, open session, drafts, lock state.

## Q4: Notifications, haptics, and other cues

### Findings
- `protocol NotificationScheduling: Sendable { requestAuthorization(); authorizationStatus(); reschedule(upcoming:) }` (`Sources/Services/NotificationService.swift:61-67`); sole impl `LocalNotificationService` (`:69`), built in `RootView.init` (`RootView.swift:20`).
- Permission: `requestAuthorization(options: [.alert, .sound, .badge])` (`NotificationService.swift:70-78`), triggered from `RootView.task` (`RootView.swift:96-110`, line 108). `canScheduleAlerts` true for `.authorized`/`.provisional` (`NotificationService.swift:57-59`). Settings deep-link when denied (`SettingsView.swift:211`).
- `reschedule` (`NotificationService.swift:84-117`): removes pending requests with prefix `"sess-"` only (`:87-88, 53`), bails if unauthorized (`:90-94`), adds `UNCalendarNotificationTrigger` (minute precision, `repeats: false`) with `sound = .default` (`:96-115`).
- `selectAlerts` caps at 64 → 32 nearest future sessions × 2 alerts, ids `sess-<UUID>-24h` / `-1h` (`:15-49`).
- Absent: `UNUserNotificationCenterDelegate`/`willPresent`, categories/actions, `UIApplicationDelegateAdaptor`, `UNTimeIntervalNotificationTrigger`.
- `ReminderCoordinator` (`@MainActor @Observable`, injected repos + `any NotificationScheduling`, `ReminderCoordinator.swift:7-24`); `refresh()` fetches upcoming + client names and reschedules (`:53-70`). Call sites: `RootView.swift:82`, `ScheduleViewModel.swift:72`, `ClientDetailViewModel.swift:57`.
- Tests: pure-function tests (`Tests/NotificationSchedulingTests.swift:9-48`, `Tests/NotificationServiceTests.swift:5-11`); `actor FakeNotifications: NotificationScheduling` recording `rescheduleCalls` (`Tests/ReminderCoordinatorTests.swift:6-19`) with in-memory container tests (`:31-72`).
- Haptics/sound: the only haptic is `.sensoryFeedback(.success, trigger: viewModel.lastLoggedSetId)` (`SessionRunView.swift:125`). No feedback generators, CoreHaptics, AVAudio, AudioServices, `WKInterfaceDevice`. Only sound is notification `.default` (`NotificationService.swift:100`). No `Timer`, `TimelineView`, or `isIdleTimerDisabled` in `Sources/`.

## Q5: Build configuration and code conventions

### Findings
- `project.yml`: iOS 26.0 (`:1-5`), `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete` (`:6-9`). Targets: `TrainMe` application (`:11-24`; team `ZD9JLCY7TF`, automatic signing, bundle `com.madacgrav.trainme`, `INFOPLIST_FILE Sources/Info.plist`, `CODE_SIGN_ENTITLEMENTS Sources/TrainMe.entitlements`) and `TrainMeTests` unit-test bundle (`:25-33`). One scheme `TrainMe` (`:34-40`). No watch, extension, or widget targets.
- `Sources/Info.plist`: portrait only (`:23-26`), calendar and Face ID usage strings (`:27-30`), empty `UILaunchScreen`. No `UIBackgroundModes`, URL types, or app-group keys.
- `Sources/TrainMe.entitlements`: empty `<dict/>` (`:4`).
- CI (`.github/workflows/ci.yml`): push to main + PRs; `macos-26`; Xcode 26; `brew install xcodegen`; `xcodegen generate`; `xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO ... test` (`:2-27`).
- View models: `@MainActor @Observable final class`, constructor-injected `any …Repository` existentials and service protocols with defaults, DTO-exposed state, async `load()`, `errorMessage` properties (`SessionRunViewModel.swift:4-73`; `ScheduleViewModel.swift:4-69`).
- Services: `Sendable` protocol + impl, often `actor` (`CalendarSyncing`/`EventKitCalendarService` `CalendarService.swift:55, 74`; `DataArchiving`/`DataArchiveActor` `DataArchive.swift:15, 28`); namespaces as enums (`MessagingService`, `ReportExporter`); logging via `Log.persistence/ui/notifications`.
- Previews: `#Preview` in feature views (e.g. `ScheduleView.swift:184, 195, 209`); `PreviewFixtures.repositories(seedingWeek:)` builds repos over an in-memory container outside the macro because `@ModelActor` inits aren't visible inside it (`Sources/Support/PreviewFixtures.swift:111-156`).
- Tests: Swift Testing only (`import Testing`, `@Test`, `#expect`; no XCTest), `PersistenceController.makeContainer(inMemory: true)` throughout, real `SwiftData…Repository` actors + fakes, `UserDefaults(suiteName: "…-\(UUID())")` isolation (`Tests/ScheduleViewModelTests.swift:1-52`; `Tests/StoreBackupTests.swift:19`).

## Q6: SwiftData store setup, migration, and cross-process access

### Findings
- `PersistenceController.makeContainer(inMemory:)` creates Application Support, builds `ModelConfiguration(isStoredInMemoryOnly:)` with no name/URL/groupContainer/cloudKit, and returns `ModelContainer(for: Schema(versionedSchema: SchemaV2.self), migrationPlan: TrainMeMigrationPlan.self, ...)` (`Sources/Persistence/PersistenceController.swift:6-22`).
- `SchemaV1` 1.0.0 frozen models (`SchemaV1.swift:8-18`); `SchemaV2` 2.0.0 uses live `Sources/Models` classes, adds `Client.isSelf` (`SchemaV2.swift:3-15`). `TrainMeMigrationPlan` single lightweight V1→V2 stage (`SchemaV1.swift:216-221`).
- Store at default location, mirrored by `AppBootstrap.storeURL = applicationSupportDirectory/default.store` (`TrainMeApp.swift:13`); `-wal`/`-shm` sidecars (`StoreBackup.swift:11`). `StoreBackup` copies to `Backups/pre-schema-<version>/` when `lastRunSchemaVersion` changes, keeps one (`:18-48, 70-72`); `restoreLatest` (`:51-68`); `RecoveryView` restore/reset (`TrainMeApp.swift:27-50, 84-109`).
- Cross-process: entitlements empty; no `groupContainer`, `containerURL(forSecurityApplicationGroupIdentifier:)`, `ModelConfiguration(url:)`, or app `UserDefaults(suiteName:)` in `Sources/`. Only data exit is the JSON archive (`DataArchive.swift:22, 67`; `SafeImporter.swift:25`; `SettingsView.swift:177-179`).
- Context access: one `ModelContainer` from `AppBootstrap` → `RootView(container:)` (`TrainMeApp.swift:69-72`; `RootView.swift:5, 15-44`), which constructs `@ModelActor actor SwiftData…Repository` instances (`ClientRepository.swift:15`, `SessionRepository.swift:128`, `WorkoutRepository.swift:13`, `ExerciseRepository.swift:13`, `ReportingQueries.swift:144`, `DataArchive.swift:27`). Repos return `Sendable` DTOs. No `@Query`, `.modelContainer(` modifier, or `mainContext` in `Sources/`; views/view models never hold a `ModelContext`.

## Cross-Cutting Observations
- **Layering:** `@MainActor @Observable` view models → `Sendable` repository/service protocols → `@ModelActor`/`actor` implementations exchanging `Sendable` DTOs. Fakes substitute protocols in tests (Q1, Q4, Q5, Q6).
- **Ephemeral run-screen state:** draft values, focused metric and the view model live in view `@State` under a push destination, and the lock gate removes the entire content tree on `.background`. Only logged `SetRecord`s persist (Q1, Q3).
- **Time in the domain:** durations are `Int` seconds with implicit units; the only per-set timestamp is `performedAt`; there are no timer, clock, or rest primitives anywhere in `Sources/` (Q2, Q4).
- **Single-process, single-target app:** no extensions, no app group, no background modes, empty entitlements, default store location (Q5, Q6).
- **Cues:** one success haptic tied to set logging; notifications are calendar-triggered session reminders managed by identifier prefix `sess-` (Q4).

## Open Areas
- `Tests/ExportReminderTests.swift` was not read.
- `.completeFileProtection` on exports (`DataArchive.swift:46`, `ReportExporter.swift:43`) is cited from earlier notes, not re-verified.
- Whether SwiftUI preserves `SetTableView` identity when `plannedEntries` order changes was not examined.
- Behaviour of `LockGateView` when Face ID is unavailable (`canEvaluatePolicy` fails → unlocked, `AppLock.swift:36-39`) on scenePhase cycles was not traced beyond the code path.
