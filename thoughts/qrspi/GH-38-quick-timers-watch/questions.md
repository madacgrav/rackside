# Research Questions

## Context
Focus on the session run feature (`Sources/Features/Session/`, `Sources/Features/Components/MetricStepper.swift`), the set/entry models and repositories (`Sources/Persistence/SchemaV1.swift`, `SchemaV2.swift`, `SessionRepository.swift`), app lifecycle and services (`Sources/TrainMeApp.swift`, `Sources/RootView.swift`, `Sources/Services/`), and build configuration (`project.yml`, `Sources/Info.plist`, `Sources/TrainMe.entitlements`, `.github/workflows/ci.yml`).

## Questions
1. Trace the session run flow end to end: how is `SessionRunView` presented from `ScheduleView` and `ClientDetailView`, how is `SessionRunViewModel` created and owned, and what is the lifecycle of the in-progress set from `SetDraft` seeding through logging a set (including what happens when the user switches exercises or dismisses the screen)?
2. How are duration-type metrics modeled and used across the stack — which `@Model` types carry `targetDuration` and logged duration, how do exercise metric definitions decide that `duration` applies, and how do those values flow through `SetDraft`, `SetTableView`/`MetricStepper`, `SessionRepository`, DTOs and the archive format? Note any per-entry fields related to rest or pacing.
3. How does the app respond to lifecycle changes today — what do `RootView`, `LockGateView`/`AppLock` and other observers do on `scenePhase` transitions, and what state (if any) survives backgrounding, app lock, or process termination?
4. How are local notifications, haptics and other user cues implemented — how do `NotificationService` and `ReminderCoordinator` request permission, schedule and cancel notifications, how are they abstracted for tests, and where is `.sensoryFeedback` used?
5. How is the project built and configured — what does `project.yml` define for targets, schemes, deployment targets, signing, Info.plist and entitlements; how does CI build and test; and what conventions (Swift 6 concurrency, `@Observable`/`@MainActor` usage, service protocols, previews) do existing view models and services follow?
6. How is the SwiftData store set up and accessed — `PersistenceController`, the schema versioning/migration plan between V1 and V2, and whether the container location, app groups, or any data-sharing mechanism exist that would let another process read or write the store?
