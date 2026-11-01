# Implementation Plan

## Overview
Adds a native new-client intake to TrainMe:
- profile fields
- a dated health screening with a medical-clearance flag
- dated NASM page-1 movement and measurement assessments
- a versioned liability waiver that is sent as a PDF and later marked returned
- a guided intake flow that ties these together

The work ships as one V2→V3 SwiftData migration and archive format v2. Older v1 export files keep
importing.

**Test command** (run after every phase):
```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```
`project.yml` uses folder sources (`Sources`, `Tests`), so new files only need `xcodegen generate`.
If xcodegen is unavailable, add the new files to the `TrainMe` or `TrainMeTests` target in Xcode by
hand. Resources under `Sources/Resources` and `Tests/Fixtures` are already picked up through the folder
sources; `seed_exercises.json` and `export-v1.json` prove this.

**Conventions for every new type** (from research.md):
- `@Model` classes give every non-init stored property a default (`Client.swift:8`).
- DTOs are `Codable, Sendable, Identifiable, Equatable` and provide `init(_ model:)` and `toModel()`
  (`ClientDTO.swift:22-61`).
- Repositories are a protocol plus a `@ModelActor actor SwiftDataXRepository` that returns DTOs
  (`ClientRepository.swift`).
- View models are `@MainActor @Observable final class` with `errorMessage`, `canSave` and
  `save() async -> Bool` (`ClientEditViewModel.swift`).
- Edit sheets are `NavigationStack { Form }`. Save is `.borderedProminent` and `.disabled(!canSave)`,
  Cancel calls `dismiss()`, and `ErrorBanner` is the last section (`ClientEditView.swift:14-55`).
- Option sets follow `MetricSet` (`Sources/Models/Exercise.swift:13-19`): `let rawValue: Int`,
  `static let x = T(rawValue: 1 << n)`. Add `Codable`, which works through RawRepresentable.
- Errors are logged with `Log.persistence` or `Log.ui` (`Sources/Support/Log.swift`).

**Deviations from structure.md**, decided while reading the code:
1. **Repository bundle.** `ClientListViewModel` and `ClientDetailViewModel` already take five
   dependencies. A `struct IntakeRepositories { health, assessments, waivers }` is passed down from
   `RootView` instead of adding three separate parameters to each.
2. **Client delete cascade.** `ClientRepository.delete(id:)` is the only cascade point. It deletes
   child rows with `modelContext.delete(model:where:)` itself, the same way `SessionRepository.swift:315-323`
   deletes SetRecords. Other repositories don't get `deleteAll(clientId:)`. (`delete(id:)` currently
   has no UI caller, but archive replace and future UI rely on it.)
3. **Waiver sharing uses a `UIActivityViewController` wrapper**, not `ShareLink`. The wrapper's
   `completionWithItemsHandler` reports `completed`, so the record is created only when a share
   actually finishes. That fixes the "ShareLink has no confirmation" risk in design.md.
4. **Store file protection.** The phase 5 review is decided now: keep the iOS default
   (complete-until-first-authentication) and document it in PRD §10. The app is already behind Face
   ID, and a stricter class risks breaking background reminder refresh. There is no code change.
5. **Measurement units.** Values are stored in metric (kg, cm). They are edited and shown in the unit
   from the existing `@AppStorage("defaultWeightUnit")` setting: lb means in and lb. Conversion
   helpers live on `Measurements`.

---

## Phase 1: Client profile and schema/archive groundwork

### Changes

#### 1. Freeze SchemaV2
**File**: `Sources/Persistence/SchemaV2.swift`
**Action**: modify

Turn `SchemaV2` into a frozen snapshot, the same way `SchemaV1` is built:
1. **Before editing any model**, copy the stored properties and `init` of the eight live classes as
   nested `@Model final class` types inside `enum SchemaV2`. The source files are
   `Sources/Models/Client.swift`, `Exercise.swift`, `Workout.swift`, `Session.swift` and `SetRecord.swift`.
   - Keep `@Attribute(.unique)`, the defaults, and the `@Relationship(deleteRule: .cascade, inverse:)`
     declarations. Inside the enum the inverse keypaths resolve to the nested types, as they do in
     `SchemaV1.swift:74,118,148`.
   - Drop computed properties and helpers.
2. `models` lists the nested types.
3. Keep `versionIdentifier` 2.0.0 and `versionString`.
4. Header comment: "Frozen snapshot of the models as shipped in 2.0 (adds `Client.isSelf`). Never
   edit."

#### 2. Add SchemaV3 and the migration stage
**File**: `Sources/Persistence/SchemaV3.swift`
**Action**: create
```swift
import SwiftData

/// Current schema: the live model classes in Sources/Models. Adds client intake
/// (profile fields, HealthScreening, Assessment, WaiverTemplate, WaiverRecord).
/// Editable until the intake branch merges; then freeze it like SchemaV2.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Exercise.self, Workout.self, WorkoutEntry.self,
         Session.self, WorkoutInstance.self, PlannedEntry.self, SetRecord.self]
        // Phase 2 appends HealthScreening.self, Phase 3 Assessment.self,
        // Phase 4 WaiverTemplate.self, WaiverRecord.self.
    }
    static var versionString: String {
        let v = versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }
}
```
**File**: `Sources/Persistence/SchemaV1.swift` (`TrainMeMigrationPlan`, :216-221)
```swift
static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
static var stages: [MigrationStage] {
    [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
     .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)]
}
```
**File**: `Sources/Persistence/PersistenceController.swift`
- Replace `SchemaV2` with `SchemaV3` in `schemaTypes` and in `Schema(versionedSchema:)`.

**File**: `Sources/TrainMeApp.swift:19`
- Change `currentVersion: SchemaV2.versionString` to `SchemaV3.versionString`.

#### 3. Client profile fields
**File**: `Sources/Models/Client.swift`
**Action**: modify. Add these after `isSelf`, all defaulted to nil, with matching `init` parameters
that default to nil:
```swift
// v3 intake profile
var dateOfBirth: Date?
var emergencyName: String?
var emergencyRelationship: String?
var emergencyPhoneE164: String?
var physicianName: String?
var physicianPhoneE164: String?
var occupation: String?
var trainingHistory: String?
var availability: String?
```
**File**: `Sources/Models/DTO/ClientDTO.swift`
- Add the same nine optionals with `= nil` defaults, declared after `isSelf`, so existing memberwise
  call sites (tests, `ClientEditViewModel`) still compile.
- Add all nine to `CodingKeys`. `isSelf` stays excluded.
- Extend `init(_:)`, `apply(to:)` and `toModel()` to carry the nine fields.

#### 4. Archive v2
**File**: `Sources/Services/Archive/ArchiveV2.swift`
**Action**: create
```swift
import Foundation

/// Version 2 of the export archive: adds client intake data. Editable until the
/// intake branch merges, then FROZEN like ArchiveV1. V1 files decode through
/// ArchiveV1.Envelope and `migrate` (new arrays empty; new optional ClientDTO
/// fields decode as nil, guarded by goldenV1FixtureImports).
enum ArchiveV2 {
    static let schemaVersion = 2

    struct Envelope: Codable, Sendable {
        var schemaVersion: Int = ArchiveV2.schemaVersion
        let exportedAt: Date
        let appVersion: String
        var clients: [ClientDTO]
        var exercises: [ExerciseDTO]
        var workouts: [WorkoutDTO]
        var sessions: [SessionDTO]
        var setRecords: [SetRecordDTO]
        // Phase 2: healthScreenings; Phase 3: assessments; Phase 4: waiverTemplate, waivers.
    }

    static func migrate(_ v1: ArchiveV1.Envelope) -> Envelope {
        Envelope(exportedAt: v1.exportedAt, appVersion: v1.appVersion, clients: v1.clients,
                 exercises: v1.exercises, workouts: v1.workouts, sessions: v1.sessions,
                 setRecords: v1.setRecords)
    }
}
```
**File**: `Sources/Services/Archive/ArchiveV1.swift`
- Move the `typealias CurrentArchive` line to `ArchiveV2.swift` as
  `typealias CurrentArchive = ArchiveV2.Envelope`.
- Leave everything else untouched. Removing the alias line is allowed, because the alias is marked
  "Repointed when a new archive version ships".

**File**: `Sources/Services/Archive/DataArchive.swift` (`importData`, :82-100). Replace the version
guard and decode with:
```swift
guard probe.schemaVersion <= ArchiveV2.schemaVersion else {
    throw ArchiveError.newerThanApp(probe.schemaVersion)
}
let envelope: CurrentArchive
do {
    switch probe.schemaVersion {
    case ...1: envelope = ArchiveV2.migrate(try decoder.decode(ArchiveV1.Envelope.self, from: data))
    default: envelope = try decoder.decode(ArchiveV2.Envelope.self, from: data)
    }
} catch {
    Log.archive.error("Envelope decode failed: \(error.localizedDescription)")
    throw ArchiveError.decodeFailed
}
```
`exportData()` keeps building `CurrentArchive(...)`, which now writes `schemaVersion: 2`.

#### 5. Client edit and detail UI
**File**: `Sources/Features/Clients/ClientEditViewModel.swift`
- New draft fields:
  - `var hasDateOfBirth: Bool` and `var dateOfBirth: Date`, which defaults to 30 years before now
    when nil
  - `emergencyName`, `emergencyRelationship`, `emergencyPhoneRaw`
  - `physicianName`, `physicianPhoneRaw`
  - `occupation`, `trainingHistory`, `availability`
  - All Strings are seeded from `existing` with `?? ""`.
- Phone validation:
  ```swift
  /// Optional phones: empty is fine, anything typed must normalize.
  var emergencyPhoneValid: Bool { emergencyPhoneRaw.isEmpty || normalizeE164(emergencyPhoneRaw) != nil }
  var physicianPhoneValid: Bool { physicianPhoneRaw.isEmpty || normalizeE164(physicianPhoneRaw) != nil }
  var canSave: Bool {
      !name.trimmingCharacters(in: .whitespaces).isEmpty && (isSelf || phoneValid)
          && emergencyPhoneValid && physicianPhoneValid
  }
  ```
- Extract DTO building into `func makeDTO() -> ClientDTO?` (nil when the phone fails), then have
  `save()` call `makeDTO()` and upsert. Empty strings become nil, and `dateOfBirth` is `hasDateOfBirth ?
  dateOfBirth : nil`. Phase 5 reuses `makeDTO()` to detect unsaved edits.
- Add `private(set) var savedClient: ClientDTO?`, set on a successful save. Phase 5 uses it.

**File**: `Sources/Features/Clients/ClientEditView.swift`
- Move the Form's sections into `struct ClientFormContent: View { @Bindable var viewModel: ClientEditViewModel }`
  in the same file.
- The sheet body becomes `Form { ClientFormContent(viewModel: viewModel); ErrorBanner(...) }`.
  Phase 5 embeds `ClientFormContent` in the intake flow.
- Add these sections after "Training":
  - **"Profile"**:
    - `Toggle("Date of birth", isOn: $viewModel.hasDateOfBirth)`
    - when on, `DatePicker("Born", selection: $viewModel.dateOfBirth, in: ...Date.now, displayedComponents: .date)`
    - `TextField("Occupation")`
    - `TextField("Training history", axis: .vertical)`
    - `TextField("Availability", axis: .vertical)`
  - **"Emergency contact"**: name, relationship, and phone with `.keyboardType(.phonePad)`. Show the
    caption "Enter a valid phone number" in `Theme.Colors.danger` when `!emergencyPhoneValid`, copying
    `ClientEditView.swift:21-25`.
  - **"Physician"**: name, and phone with the same caption pattern.

**File**: `Sources/Features/Clients/ClientDetailView.swift`
- After "Contact", add `Section("Profile")`, shown only when at least one profile field is non-nil.
  It contains `LabeledContent` rows:
  - age, computed as `Calendar.current.dateComponents([.year], from: dob, to: .now).year` and shown
    as "34 (Mar 4, 1991)"
  - occupation, training history, availability
  - "Emergency": name, relationship and phone
  - "Physician": name and phone
- Apply `.themedRows()`.

**File**: `Sources/Support/PreviewFixtures.swift`
- Give `client` a DOB, an emergency contact and an occupation so previews show the new section.

#### 6. Tests
**File**: `Tests/SchemaTests.swift`
- Add `#expect(SchemaV3.models.count == 8)` and `#expect(SchemaV3.versionString == "3.0.0")`.
- Change the plan assertions to `schemas.count == 3` and `stages.count == 2`.
- The entity count stays 8 in this phase. Each later phase bumps it.

**File**: `Tests/MigrationTests.swift`
**Action**: create
```swift
@Test func v2StoreOpensAsV3WithClientIntact() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mig-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "test.store")
    let id = UUID()
    do {  // write a V2 store with the frozen V2 classes
        let v2 = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                    configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(v2)
        ctx.insert(SchemaV2.Client(id: id, name: "Pat", phoneE164: "+15551230000", injuries: "Knee"))
        try ctx.save()
    }
    let v3 = try ModelContainer(for: Schema(versionedSchema: SchemaV3.self),
                                migrationPlan: TrainMeMigrationPlan.self,
                                configurations: ModelConfiguration(url: url))
    let clients = try ModelContext(v3).fetch(FetchDescriptor<Client>())
    #expect(clients.count == 1)
    #expect(clients.first?.id == id && clients.first?.injuries == "Knee")
    #expect(clients.first?.emergencyName == nil && clients.first?.dateOfBirth == nil)
}
```
If SwiftData refuses to open two schemas over the same entity names in one process, put the V2 write
in a separate helper that releases its container before the V3 open (scope block, as above). Phases
2–4 extend this test by inserting nothing new: new entities start empty. Later phases also assert
that `fetch(FetchDescriptor<HealthScreening>())` and the other new types return empty.

**File**: `Tests/ArchiveRoundTripTests.swift`
- `goldenV1FixtureImports` must stay unchanged and green.
- Add `profileFieldsRoundTrip`: upsert a client with all nine fields, export, replace-import into a
  fresh env, and assert equality.
- Add `exportWritesSchemaVersion2`: decode `VersionProbe` from `exportData()` and expect 2.

**File**: `Tests/ClientRepositoryTests.swift`
- Add `exportIncludesProfileFields`: encode a ClientDTO with `emergencyName` and assert the key is in
  the JSON.

### Verification
#### Automated
- [x] Test command passes. All existing tests stay green, including `goldenV1FixtureImports`,
  `newerSchemaVersionRejected` and `exportOmitsIsSelf`.
- [x] `MigrationTests.v2StoreOpensAsV3WithClientIntact` passes.
- [x] `SchemaTests` reports 3 schemas and 2 stages.
#### Manual
- [ ] Simulator: edit a client, fill in DOB, emergency contact and physician, save, and confirm the
  detail screen's Profile section shows the age and contacts.
- [ ] A bad emergency phone disables Save and shows the caption.

---

## Phase 2: Health screening and medical clearance

### Changes

#### 1. Model, DTO, logic
**File**: `Sources/Models/HealthScreening.swift`
**Action**: create
```swift
struct ScreeningAnswers: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int
    static let heartOrBloodPressure = ScreeningAnswers(rawValue: 1 << 0)
    static let chestPain = ScreeningAnswers(rawValue: 1 << 1)
    static let dizzinessOrFainting = ScreeningAnswers(rawValue: 1 << 2)
    static let otherChronicCondition = ScreeningAnswers(rawValue: 1 << 3)
    static let chronicMedication = ScreeningAnswers(rawValue: 1 << 4)
    static let boneJointSoftTissue = ScreeningAnswers(rawValue: 1 << 5)
    static let supervisedOnly = ScreeningAnswers(rawValue: 1 << 6)

    /// The app's own wording (not PAR-Q+ text), in display order.
    static let questions: [(ScreeningAnswers, String)] = [
        (.heartOrBloodPressure, "Has a doctor ever told you that you have a heart condition or high blood pressure?"),
        (.chestPain, "Do you feel pain or pressure in your chest at rest, during daily activities, or when active?"),
        (.dizzinessOrFainting, "In the last 12 months, have you lost your balance because of dizziness, or passed out?"),
        (.otherChronicCondition, "Have you been diagnosed with another long-term medical condition?"),
        (.chronicMedication, "Do you currently take prescription medication for a long-term condition?"),
        (.boneJointSoftTissue, "Do you have a bone, joint, muscle, or ligament problem (now or in the last 12 months) that activity could make worse?"),
        (.supervisedOnly, "Has a doctor said you should only be physically active under medical supervision?"),
    ]
}

enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, vigorous
    var title: String { rawValue.capitalized }
}

@Model
final class HealthScreening {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var completedOn: Date
    var answersRaw: Int = 0
    var conditions: String?
    var surgeries: String?
    var medications: String?
    var familyHeartHistory: Bool = false
    var symptoms: String?
    var sleepHours: Double?
    var stressLevel: Int?          // 1...5
    var tobacco: Bool = false
    var alcoholPerWeek: Int?
    var activityLevelRaw: String?
    var clearanceReceivedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    // init with all params defaulted except clientId and completedOn
}
```
**File**: `Sources/Models/DTO/HealthScreeningDTO.swift`
**Action**: create
- Mirror the model, using typed `answers: ScreeningAnswers` and `activityLevel: ActivityLevel?`.
- Provide `init(_:)`, `toModel()` and `apply(to:)`.
- Add the pure logic:
```swift
enum ClearanceStatus: Equatable, Sendable {
    case notScreened, clear, needed, received(Date)
}

extension HealthScreeningDTO {
    static let reviewInterval = DateComponents(month: 12)

    /// Latest screening decides: any YES without a clearance date → needed.
    static func clearance(for latest: HealthScreeningDTO?) -> ClearanceStatus {
        guard let latest else { return .notScreened }
        guard !latest.answers.isEmpty else { return .clear }
        if let on = latest.clearanceReceivedOn { return .received(on) }
        return .needed
    }

    static func reviewDue(_ latest: HealthScreeningDTO?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let latest, let due = calendar.date(byAdding: reviewInterval, to: latest.completedOn) else { return false }
        return now >= due
    }
}
```

#### 2. Repository and bundle
**File**: `Sources/Persistence/HealthScreeningRepository.swift`
**Action**: create
```swift
protocol HealthScreeningRepository: Sendable {
    func forClient(_ clientId: UUID) async throws -> [HealthScreeningDTO]   // newest completedOn first
    func latest(clientId: UUID) async throws -> HealthScreeningDTO?
    func upsert(_ dto: HealthScreeningDTO) async throws
    func delete(id: UUID) async throws
}
```
- Implement it as `@ModelActor actor SwiftDataHealthScreeningRepository`.
- `latest` uses `fetchLimit = 1` with `SortDescriptor(\.completedOn, order: .reverse)`.

**File**: `Sources/Persistence/IntakeRepositories.swift`
**Action**: create
```swift
/// Client-intake repositories, passed down together from RootView.
struct IntakeRepositories: Sendable {
    let health: any HealthScreeningRepository
    // Phase 3: let assessments: any AssessmentRepository
    // Phase 4: let waivers: any WaiverRepository

    init(container: ModelContainer) {
        health = SwiftDataHealthScreeningRepository(modelContainer: container)
    }
}
```
`IntakeRepositories(container:)` is a plain `init`, not a macro, so `PreviewFixtures` can call it.

#### 3. Cascade, schema, archive
- **`Sources/Persistence/ClientRepository.swift`, `delete(id:)`**: before `modelContext.delete(existing)`,
  add:
  ```swift
  // Intake rows link by clientId, not a relationship, so the delete is explicit
  // (same as SetRecords in SessionRepository).
  try modelContext.delete(model: HealthScreening.self, where: #Predicate { $0.clientId == id })
  ```
- **`SchemaV3.models`**: append `HealthScreening.self`.
- **`ArchiveV2.Envelope`**: add `var healthScreenings: [HealthScreeningDTO]`. `migrate` passes `[]`.
- **`DataArchive.swift`**:
  - `exportData` fetches `HealthScreening` and maps it with `HealthScreeningDTO.init`.
  - `deleteAll` adds `try modelContext.delete(model: HealthScreening.self)` first.
  - `upsertAll` loops: delete the existing row with the same id, then insert `dto.toModel()`, like
    SetRecords (:166-172).

#### 4. UI
**File**: `Sources/Features/Health/HealthScreeningEditViewModel.swift`
**Action**: create
- `init(repo:, clientId:, existing: HealthScreeningDTO?)`.
- Draft fields:
  - `answers: ScreeningAnswers`, `completedOn: Date`
  - text fields, `familyHeartHistory`
  - `hasSleep`/`sleepHours`, `stressLevel: Int` with 0 meaning unset, `tobacco`,
    `alcoholPerWeek: Int`, `activityLevel: ActivityLevel?`
  - `hasClearance`/`clearanceReceivedOn`, `notes`
- `func binding(for q: ScreeningAnswers) -> Bool` / `func set(_ q:, _ on: Bool)`.
- `var anyYes: Bool`.
- `canSave` is always true.
- `makeDTO()` and `save()` follow phase 1, with the message "Couldn't save the screening. Please try
  again."
- `savedScreening`.

**File**: `Sources/Features/Health/HealthScreeningEditView.swift`
**Action**: create
- `struct HealthScreeningFormContent: View`, with these sections:
  - **"Screening"**: a `DatePicker` for completedOn.
  - **"Questions"**: `ForEach(ScreeningAnswers.questions)` rows, each with the question text and a
    `Picker` (`.segmented`, No/Yes) bound through `Binding(get:set:)`. Footer: "Any YES means
    medical clearance is recommended before training. This screening is not a diagnosis."
  - **"Clearance"**: shown when `anyYes`, with `Toggle("Clearance received")` and a DatePicker.
  - **"Medical history"**: conditions, surgeries, medications, `Toggle("Family history of heart
    disease before 55 (men) / 65 (women)")`, symptoms.
  - **"Lifestyle"**:
    - `OptionalStepper` for sleep hours, range 0...14, step 0.5 (`WorkoutBuilderView.swift:179-208`;
      move `OptionalStepper` and `AdaptiveLabeledRow` into `Sources/Features/Components/` unchanged
      so both features can use them)
    - stress picker 1–5
    - `Toggle("Uses tobacco")`
    - drinks per week stepper
    - activity picker
  - **"Notes"**.
- `HealthScreeningEditView` is the sheet wrapper: title "Health Screening", plus Save and Cancel per
  the conventions.

**File**: `Sources/Features/Health/ClearanceBadge.swift`
**Action**: create
- A small view that renders a `ClearanceStatus`:
  - `.needed` shows `Label("Medical clearance recommended", systemImage: "cross.case.fill")` in
    `Theme.Colors.warning`.
  - `.received(d)` shows "Clearance received <date>" in secondary style.
  - `.clear` shows "No screening flags".
  - `.notScreened` shows "Not screened yet".

**File**: `Sources/Features/Clients/ClientDetailViewModel.swift`
- Add `let intake: IntakeRepositories` as an init parameter.
- Add `var screenings: [HealthScreeningDTO] = []` and computed values:
  - `var clearance: ClearanceStatus { .clearance(for: screenings.first) }`
  - `var screeningReviewDue: Bool { .reviewDue(screenings.first, now: .now) }`
- `reload()` loads `try await intake.health.forClient(client.id)`. On failure it logs and falls back
  to `[]`, the same pattern as sessions.

**File**: `Sources/Features/Clients/ClientDetailView.swift`
- After "Profile", add `Section("Health & Clearance")` containing:
  - `ClearanceBadge(status: viewModel.clearance)`
  - when `screeningReviewDue`, a `Label("Screening is over 12 months old — review it", systemImage: "clock.badge.exclamationmark")`
  - a row "Latest screening <date>" that opens the edit sheet for `screenings.first`
  - a `Button("New screening")` that opens the sheet with `existing: nil`
- Use `.sheet(item:)` with an `Identifiable` wrapper: `struct ScreeningSheet: Identifiable { let id = UUID(); let existing: HealthScreeningDTO? }`.
- On save, reload.
- In `sessionLink`, pass `healthRepo: viewModel.intake.health`.

**File**: `Sources/Features/Clients/ClientListViewModel.swift`, `ClientListView.swift`
- Add `let intake: IntakeRepositories` to the init and pass it to `ClientDetailViewModel`.

**File**: `Sources/RootView.swift`
- Build `let intake = IntakeRepositories(container: container)` inside `body` (or as a stored
  property set in `init`).
- Pass it to `ClientListViewModel` and `ScheduleViewModel`.

**File**: `Sources/Features/Session/SessionRunViewModel.swift`
- Add the init parameter `healthRepo: (any HealthScreeningRepository)? = nil`, stored privately, and
  `var clearanceNeeded = false`.
- At the end of `load()`:
  ```swift
  if let healthRepo {
      let latest = try? await healthRepo.latest(clientId: session.clientId)
      clearanceNeeded = HealthScreeningDTO.clearance(for: latest) == .needed
  }
  ```

**File**: `Sources/Features/Session/SessionRunView.swift:47-55`
- Show the injuries section when there are injuries **or** `clearanceNeeded`.
- Inside it, add `Label("Medical clearance recommended", systemImage: "cross.case.fill")` in
  `Theme.Colors.warning` when the flag is set.
- Header: "Health & limitations".

**File**: `Sources/Features/Schedule/ScheduleViewModel.swift`, `ScheduleView.swift:99-110`
- `ScheduleViewModel.init` gets `healthRepo: (any HealthScreeningRepository)? = nil`, stored as
  `let healthRepo`.
- `sessionLink` passes `healthRepo: viewModel.healthRepo`.
- Existing tests keep compiling because of the default.

**File**: `Sources/Support/PreviewFixtures.swift`
- Add `let intake: IntakeRepositories` to `Repositories` and build it in `repositories()`.
- Add `static let screening = HealthScreeningDTO(... answers: [.boneJointSoftTissue], clearanceReceivedOn: nil ...)`
  for `client` and insert it in `container()`.
- Update the call sites that the compiler flags in `ClientDetailView`/`ClientListView` previews.
- Add a `#Preview("Health screening")` for the edit sheet.

#### 5. Tests
**File**: `Tests/HealthScreeningTests.swift`
**Action**: create. Use an in-memory env, as `ArchiveRoundTripTests.makeEnv` does.
- `clearanceStates`:
  - nil gives `notScreened`
  - empty answers give `clear`
  - a YES gives `needed`
  - a YES plus a date gives `received`
- `reviewDueAfter12Months`: 11 months is false, and 12 months plus 1 day is true. Use a fixed
  calendar and dates.
- `forClientNewestFirstAndLatest`: two screenings, ordering, `latest`.
- `answersRoundTripThroughModel`: the raw value is preserved.
- `deletingClientDeletesScreenings`: upsert a client and a screening, call `clients.delete(id:)`, and
  expect `forClient` to be empty.
- `screeningsRoundTripThroughArchive`: export, replace-import into a fresh env, and compare.

**Update**:
- `Tests/SchemaTests.swift`: `SchemaV3.models.count == 9` and entities 9.
- `MigrationTests`: assert `FetchDescriptor<HealthScreening>()` is empty after migration.
- `Tests/SessionRunViewModelTests.swift`: add `clearanceFlagLoaded`, built with a health repo over
  the same container.

### Verification
#### Automated
- [x] Test command passes.
- [x] `HealthScreeningTests` (6 tests) pass, and the updated `SchemaTests`/`MigrationTests` pass.
#### Manual
- [ ] Add a screening with one YES. Client detail shows "Medical clearance recommended", and opening
  one of the client's sessions shows the same warning.
- [ ] Edit the screening, toggle "Clearance received" with a date, and confirm detail shows
  "Clearance received <date>" and the session warning is gone.

---

## Phase 3: Movement and measurement assessments

### Changes

#### 1. Model, DTO, diff
**File**: `Sources/Models/Assessment.swift`
**Action**: create
```swift
struct AssessmentSections: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int
    static let measurements = AssessmentSections(rawValue: 1 << 0)
    static let overheadSquat = AssessmentSections(rawValue: 1 << 1)
    static let singleLegSquat = AssessmentSections(rawValue: 1 << 2)
    static let all: AssessmentSections = [.measurements, .overheadSquat, .singleLegSquat]
}

/// Overhead Squat — anterior view, scored per side.
struct OHSAnterior: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int
    static let footTurnsOut = OHSAnterior(rawValue: 1 << 0)
    static let kneeMovesInward = OHSAnterior(rawValue: 1 << 1)
    static let kneeMovesOutward = OHSAnterior(rawValue: 1 << 2)
    static let items: [(OHSAnterior, String)] = [(.footTurnsOut, "Foot turns out"),
        (.kneeMovesInward, "Knee moves inward"), (.kneeMovesOutward, "Knee moves outward")]
}
/// Lateral view (right side), yes/no.
struct OHSLateral: OptionSet, ... { excessiveForwardLean, lowBackArches, lowBackRounds, armsFallForward; items }
/// Posterior view, scored per side.
struct OHSPosterior: OptionSet, ... { heelRises, footFlattens, asymmetricalWeightShift; items }
/// Modified retests (heels elevated / arms down): regions where the compensation resolved.
struct OHSRegions: OptionSet, ... { feet, knees, lphc, upperBody; items: "Feet","Knees","LPHC","Upper body" }
/// Single Leg Squat, scored per leg.
struct SLSCompensations: OptionSet, ... { footFlattens, kneeMovesInward, kneeMovesOutward,
    hipHike, hipDrop, inwardTrunkRotation, outwardTrunkRotation; items }

struct Measurements: Codable, Equatable, Sendable {
    var restingHR: Int?
    var systolic: Int?
    var diastolic: Int?
    var heightCm: Double?
    var weightKg: Double?
    var waistCm: Double?
    var hipCm: Double?
    var bodyFatPct: Double?
    var pushUps: Int?
    var plankSeconds: Int?
    var waistToHip: Double? { guard let w = waistCm, let h = hipCm, h > 0 else { return nil }; return w / h }
    var bmi: Double? { guard let h = heightCm, let w = weightKg, h > 0 else { return nil }; return w / pow(h / 100, 2) }
    static let cmPerInch = 2.54, kgPerLb = 0.45359237
}

@Model
final class Assessment {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var performedOn: Date
    var sectionsRaw: Int = 0
    var measurementsData: Data?           // JSON Measurements, like Session.recurrenceData
    var ohsAnteriorRightRaw: Int = 0
    var ohsAnteriorLeftRaw: Int = 0
    var ohsLateralRaw: Int = 0
    var ohsPosteriorRightRaw: Int = 0
    var ohsPosteriorLeftRaw: Int = 0
    var ohsHeelsElevatedRaw: Int = 0
    var ohsArmsDownRaw: Int = 0
    var ohsNotes: String?
    var slsRightRaw: Int = 0
    var slsLeftRaw: Int = 0
    var slsNotes: String?
    var createdAt: Date
    var updatedAt: Date
}
```
The `items` tables carry the exact labels from the form (see task.md).

**File**: `Sources/Models/DTO/AssessmentDTO.swift`
**Action**: create
- Use typed fields: `sections`, `measurements: Measurements` (an empty struct when the data is nil),
  `ohsAnteriorRight` and the other option sets.
- Provide `init(_:)`, which decodes `measurementsData` with `try? JSONDecoder()`, plus `toModel()`
  and `apply(to:)`, which encode it.
- Add the diff:
```swift
struct AssessmentDiff: Equatable, Sendable {
    var resolved: [String] = []   // "Overhead squat · Anterior · Right: Knee moves inward"
    var new: [String] = []
    var measurementDeltas: [(label: String, delta: Double)] = []  // weight, waist, hip, body fat, resting HR, push-ups, plank
    var isEmpty: Bool { resolved.isEmpty && new.isEmpty && measurementDeltas.isEmpty }
    static func == ... // compare labels + rounded deltas
}

extension AssessmentDTO {
    /// What changed versus the previous assessment; only sections present in BOTH are compared.
    static func diff(_ current: AssessmentDTO, previous: AssessmentDTO?) -> AssessmentDiff
}
```
How the diff is built:
- Add a helper `func compare<T: OptionSet>(_ cur: T, _ prev: T, items: [(T, String)], prefix: String)`
  where `T.Element == T`. It appends labels for items set in `prev` but not in `cur` to `resolved`,
  and items set in `cur` but not in `prev` to `new`.
- Call it once per field.
- Measurement deltas cover only fields that are non-nil in both assessments, with `cur - prev`.

#### 2. Repository, cascade, schema, archive
**File**: `Sources/Persistence/AssessmentRepository.swift`
**Action**: create
```swift
protocol AssessmentRepository: Sendable {
    func forClient(_ clientId: UUID) async throws -> [AssessmentDTO]                // newest first
    func previous(before date: Date, clientId: UUID) async throws -> AssessmentDTO? // performedOn < date, newest
    func upsert(_ dto: AssessmentDTO) async throws
    func delete(id: UUID) async throws
}
```
- `IntakeRepositories`: add `let assessments: any AssessmentRepository`.
- `ClientRepository.delete(id:)`: add a matching delete for `Assessment`.
- `SchemaV3.models`: append `Assessment.self`.
- `ArchiveV2.Envelope`: add `var assessments: [AssessmentDTO]`, and have `migrate` pass `[]`.
- `DataArchive`: handle `Assessment` in export, `deleteAll` and `upsertAll`, the same way as
  HealthScreening.

#### 3. UI
**File**: `Sources/Features/Assessments/CompensationGrid.swift`
**Action**: create
- A generic view over `T: OptionSet`. Its parameters are:
  - `items: [(T, String)]`
  - `right: Binding<T>?` and `left: Binding<T>`, plus an optional `single: Binding<T>` for yes/no
    views
- Each item renders as an `AdaptiveLabeledRow`: the label, then `.bordered` buttons "R" and "L" (or
  "Yes").
- A selected button is tinted `Theme.Colors.accent`, otherwise `Color.secondary`, the same pattern as
  `SessionEditView.swift:126-139`.
- Each button has an accessibility label such as "Knee moves inward, right side" and an `.isSelected`
  trait when on.

**File**: `Sources/Features/Assessments/AssessmentEditViewModel.swift`
**Action**: create
- `init(repo:, clientId:, existing: AssessmentDTO?, sections: AssessmentSections = .all, weightUnit: Unit)`.
- Draft fields:
  - `performedOn`, `sections`
  - per-field option-set vars
  - measurements, held as display-unit draft values: `weight`, `height`, `waist` and `hip` as
    `Double?` in lb/in when `weightUnit == .lb`, converted with `Measurements.kgPerLb`/`cmPerInch` in
    `makeDTO()`
  - notes
- `canSave` requires `!sections.isEmpty`.
- `save()` keeps a stable id (`existing?.id ?? draftId`) so phase 5 can save the same assessment
  repeatedly.
- `savedAssessment`.

**File**: `Sources/Features/Assessments/AssessmentEditView.swift`
**Action**: create. Split the content into two views so phase 5 can show them as separate steps.

**`MeasurementsFormContent`** has three sections:
- "Vitals": resting HR, systolic, diastolic.
- "Body": height, weight, waist, hip, body fat %. Show computed BMI and WHR rows when available.
- "Fitness": push-ups, plank seconds.
- Each field uses `OptionalStepper`, with the unit in its label, e.g. "Weight (lb)".

**`MovementFormContent`** has these sections:
- "Overhead Squat — Anterior": `CompensationGrid` with R/L.
- "Lateral (right side)": Yes.
- "Posterior": R/L.
- "Modified — Heels elevated" and "Modified — Arms down": an `OHSRegions` grid with Yes. Footer:
  "Mark the regions where the compensation went away."
- "Overhead Squat notes".
- "Single Leg Squat": an R/L grid.
- "Single Leg Squat notes".
- Only the sections included in `sections` are shown.

**`AssessmentEditView`** is the sheet:
- A "Sections" toggle section on top (Measurements, Overhead Squat, Single Leg Squat).
- Then a `DatePicker`, then the two contents.
- Title: "Assessment".

**File**: `Sources/Features/Assessments/AssessmentDetailView.swift`
**Action**: create. A pushed `List` with `themedScreen()`. It takes the assessment, an optional
previous assessment, and an `onEdit` closure.
- Sections, in order:
  - "Changes since <previous date>": resolved items in `Theme.Colors.success` with a
    "checkmark.circle" icon, new items in `Theme.Colors.warning`, and deltas such as "Weight −2.0 lb".
    It shows "First assessment" when there is no previous one.
  - Measurements as `LabeledContent`.
  - Overhead squat findings, grouped by view and side, listing only the selected items, or "No
    compensations".
  - Single leg squat findings.
  - Notes.
- Toolbar "Edit" opens the edit sheet.

**File**: `ClientDetailViewModel` and `ClientDetailView`
- The view model loads `assessments` with `intake.assessments.forClient`.
- Add `Section("Assessments")`:
  - a `Button("New assessment")` that opens the sheet
  - a `ForEach` of `NavigationLink` rows: the date, plus a caption listing the included sections
    (e.g. "Measurements · OHS · SLS"). Each opens `AssessmentDetailView` with `previous` set to the
    next element in the newest-first array.
- The view reads `@AppStorage("defaultWeightUnit")` and passes the unit into the edit view model.

**File**: `Sources/Support/PreviewFixtures.swift`
- Add two `assessment` fixtures for `client`, a month apart, where one compensation resolves.
- Add previews for the edit sheet, `MovementFormContent` and the detail view.

#### 4. Tests
**File**: `Tests/AssessmentTests.swift`
**Action**: create
- `optionSetsRoundTripThroughModel`: every raw field, and measurements JSON in and out.
- `diffResolvedAndNew`: the previous assessment has knee-inward on the right; the current one has
  foot-turns-out on the left. Expect one resolved and one new, with the exact labels.
- `diffMeasurementDeltasOnlyWhenBothPresent`.
- `diffIgnoresSectionsMissingFromEither`.
- `diffWithNoPreviousIsEmpty`.
- `bmiAndWaistToHip`.
- `editViewModelConvertsPoundsToKg`: weight 200 in lb is saved as 90.718474 kg (±0.001).
- `forClientNewestFirstAndPrevious`.
- `deletingClientDeletesAssessments`.
- `assessmentsRoundTripThroughArchive`.

**Update**:
- `SchemaTests`: 10 models and 10 entities.
- `MigrationTests`: assert the `Assessment` fetch is empty.

### Verification
#### Automated
- [x] Test command passes. The 10 new `AssessmentTests` pass.
#### Manual
- [ ] Create two assessments for a client, a month apart, with one compensation removed. The second
  one's detail shows it under "resolved", plus a weight delta.
- [ ] The editor stays usable at Accessibility XL text size (rows stack). VoiceOver reads "Knee moves
  inward, right side, selected".

---

## Phase 4: Liability waiver (send and mark returned)

### Changes

#### 1. Models, DTOs, status
**File**: `Sources/Models/Waiver.swift`
**Action**: create
```swift
@Model
final class WaiverTemplate {
    @Attribute(.unique) var id: UUID
    var version: Int = 1
    var body: String = ""
    var updatedAt: Date
}

@Model
final class WaiverRecord {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var sentOn: Date
    var templateVersion: Int = 1
    var templateBody: String = ""        // snapshot of exactly what was sent
    var returnedSignedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}
```
**File**: `Sources/Models/DTO/WaiverDTO.swift`
**Action**: create
- `WaiverTemplateDTO` and `WaiverRecordDTO`, following the conventions.
- Status logic:
```swift
enum WaiverStatus: Equatable, Sendable { case none, sent(Date), signed(Date) }
extension WaiverRecordDTO {
    /// Newest record decides; any signed record wins over a later unsigned resend.
    static func status(_ records: [WaiverRecordDTO]) -> WaiverStatus {
        if let signed = records.compactMap(\.returnedSignedOn).max() { return .signed(signed) }
        if let sent = records.map(\.sentOn).max() { return .sent(sent) }
        return .none
    }
}
```

#### 2. Starter text
**File**: `Sources/Resources/waiver_starter.txt`
**Action**: create. Plain text. Lines in ALL CAPS are rendered as headings, and the rest as
paragraphs.
- The first line is "PERSONAL TRAINING WAIVER, RELEASE OF LIABILITY, AND ASSUMPTION OF RISK".
- The sections are:
  - PARTICIPATION
  - ASSUMPTION OF RISK
  - RELEASE AND WAIVER: names "ordinary negligence"
  - MEDICAL ACKNOWLEDGEMENT: health screening disclosure and medical clearance
  - EMERGENCY TREATMENT CONSENT
  - ENTIRE AGREEMENT AND SEVERABILITY
  - ACKNOWLEDGEMENT: "I have read this document, understand it, and sign it voluntarily."
- The last lines are `Client initials: ______`, `Client signature: ______________  Date: ________`
  and `Trainer signature: ______________  Date: ________`.
- Mark the risk-assumption and release paragraphs for bold rendering by starting them with `!! `. The
  renderer strips the marker and draws them bold, which gives the "conspicuous" formatting the
  research calls for.
- Keep the text generic and plain-language, and add no state-specific clauses.
- The top of the file carries the comment line `# Template — not legal advice. Have it reviewed by
  your attorney or insurer.` Lines starting with `#` are skipped by the renderer.

#### 3. Repository, cascade, schema, archive
**File**: `Sources/Persistence/WaiverRepository.swift`
**Action**: create
```swift
protocol WaiverRepository: Sendable {
    /// The single template row, created from waiver_starter.txt on first use.
    func template() async throws -> WaiverTemplateDTO
    /// Saves the body; bumps `version` only when the text actually changed.
    func saveTemplate(body: String) async throws -> WaiverTemplateDTO
    func records(clientId: UUID) async throws -> [WaiverRecordDTO]        // newest sentOn first
    /// Snapshots the current template into a new record.
    func recordSent(clientId: UUID, on date: Date) async throws -> WaiverRecordDTO
    func markReturned(id: UUID, on date: Date?) async throws               // nil clears
    func delete(id: UUID) async throws
}
```
- The starter text loads with `Bundle.main.url(forResource: "waiver_starter", withExtension: "txt")`.
- If the file is missing, fall back to a one-line placeholder and log it with `Log.persistence`.
- Make the loader `static func starterText(bundle: Bundle = .main) -> String` so tests can call it.

Wiring:
- `IntakeRepositories`: add `let waivers: any WaiverRepository`.
- `ClientRepository.delete(id:)`: add a delete for `WaiverRecord`.
- `SchemaV3.models`: append `WaiverTemplate.self` and `WaiverRecord.self`.
- `ArchiveV2.Envelope`: add `var waiverTemplate: WaiverTemplateDTO?` and `var waivers: [WaiverRecordDTO]`.
  `migrate` passes nil and `[]`.
- `DataArchive`:
  - export includes the first `WaiverTemplate`, mapped to its DTO, and all records
  - `deleteAll` deletes both types
  - upsert, records: delete by id and insert
  - upsert, template when non-nil: delete every `WaiverTemplate`, then insert

#### 4. PDF renderer
**File**: `Sources/Services/WaiverPDFRenderer.swift`
**Action**: create
```swift
import UIKit

enum WaiverPDFRenderer {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter, like ReportExporter
    static let margin: CGFloat = 54
    static let directory = FileManager.default.temporaryDirectory.appending(path: "Waivers", directoryHint: .isDirectory)

    /// Paginated text PDF; written with complete protection (holds client PII).
    static func render(body: String, clientName: String, trainerName: String?, version: Int, date: Date) throws -> URL {
        removeAll()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Waiver - \(sanitized(clientName)).pdf")
        let text = attributed(body: body, clientName: clientName, trainerName: trainerName, version: version, date: date)
        let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            var range = CFRange(location: 0, length: 0)
            var page = 0
            repeat {
                ctx.beginPage()
                page += 1
                let frameRect = pageRect.insetBy(dx: margin, dy: margin)
                // Core Text draws in a flipped space.
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageRect.height); cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: frameRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                let visible = CTFrameGetVisibleStringRange(frame)
                range = CFRange(location: visible.location + visible.length, length: 0)
                footer(page: page, version: version)   // "Template v3 · Page 2" bottom-left, 9pt gray
            } while range.location < text.length
        }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func removeAll() { try? FileManager.default.removeItem(at: directory) }
}
```
- **`attributed(...)`**:
  1. Starts with a header block: the title in bold 16pt, then "Client: <name>", "Trainer: <name or
     ______>" and "Prepared <date, abbreviated>".
  2. Then goes line by line through the body:
     - skip `#` lines
     - ALL-CAPS lines are bold 12pt with spacing before
     - `!! ` lines are bold 10.5pt
     - other lines are regular 10.5pt
     - blank lines are paragraph breaks
- **`sanitized`** matches `ReportExporter.swift:61-64` (replaces `/` and `:` with `-`). Copy the
  three-line helper rather than refactoring ReportExporter.

#### 5. Share sheet with completion
**File**: `Sources/Features/Components/ActivityShareSheet.swift`
**Action**: create
```swift
/// UIActivityViewController wrapper that reports whether the share completed —
/// ShareLink cannot, and the waiver must only be marked sent when it was.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
```

#### 6. UI
**File**: `Sources/Features/Waiver/ClientWaiverViewModel.swift`
**Action**: create
- `init(repo: any WaiverRepository, clientRepo: any ClientRepository, client: ClientDTO)`.
- State: `records`, `var status: WaiverStatus`, `var pdfURL: URL?`, `errorMessage`.
- `load()`.
- `preparePDF() async`:
  1. fetch the template
  2. fetch the trainer name with `clientRepo.selfClient()?.name`
  3. call `WaiverPDFRenderer.render`
  4. set `pdfURL`
  5. on error, set "Couldn't create the waiver PDF."
- `shareFinished(completed: Bool) async`: if completed, call `recordSent(clientId:on: .now)`. In all
  cases, clear `pdfURL` and call `WaiverPDFRenderer.removeAll()`, then reload.
- `markReturned(_ record:, on:)` and `clearReturned(_:)`.

**File**: `Sources/Features/Waiver/ClientWaiverSection.swift`
**Action**: create. A `Section("Waiver")` for client detail, also reused in the phase 5 flow.
- The status row shows one of:
  - "No waiver sent"
  - "Sent <date> — awaiting signature", in warning colour
  - "Signed — returned <date>", in success colour with "checkmark.seal.fill"
- `Button("Send waiver…", systemImage: "square.and.arrow.up")` runs `preparePDF()`. When `pdfURL` is
  set, present `.sheet(item:)` with `ActivityShareSheet(items: [url]) { completed in Task { await vm.shareFinished(completed: completed) } }`.
- For the newest unsigned record, `Button("Mark signed & returned…")` presents a small sheet with a
  `DatePicker` (default today) and Save, using `.presentationDetents([.medium])`.
- `DisclosureGroup("History")` lists every record with its sent date, version and returned date. A
  swipe action on a row clears the returned date.

**File**: `Sources/Features/Waiver/WaiverTemplateEditView.swift`
**Action**: create. Pushed from Settings.
- A `Form` with a "Template v<version>" header.
- A `TextEditor` bound to the draft body, `.frame(minHeight: 360)`, with a monospaced footnote that
  explains the syntax: "Lines in ALL CAPS become headings; start a line with !! to make it bold;
  lines starting with # are hidden."
- A fixed notice section, warning-tinted, with "exclamationmark.shield.fill":
  "This template is not legal advice. Waiver rules vary by state — have it reviewed by your attorney
  or insurer before use."
- Toolbar: Save (disabled when unchanged), then `saveTemplate`.
- `Button("Reset to starter text", role: .destructive)` behind a confirmationDialog. It sets the draft
  to `SwiftDataWaiverRepository.starterText()`, and the trainer still has to tap Save.

**File**: `Sources/Features/Settings/SettingsView.swift`
- Add the init parameter `waivers: any WaiverRepository`.
- Add a new section between "Units" and "Backup": header "Client intake" with
  `NavigationLink("Liability waiver template") { WaiverTemplateEditView(repo: waivers) }`. Footer:
  "Sent to new clients as a PDF to sign and return."
- Update `RootView` (`waivers: intake.waivers`) and the Settings preview.

**File**: `ClientDetailView`
- After "Health & Clearance", add `ClientWaiverSection(viewModel: ClientWaiverViewModel(repo: viewModel.intake.waivers, clientRepo: viewModel.repository, client: viewModel.client))`.
- Hold that view model in `@State` and create it once, in `.task`. Use an optional `@State var
  waiverVM` and build it when it is nil.

#### 7. Tests
**File**: `Tests/WaiverTests.swift`
**Action**: create
- `templateSeedsFromStarterText`: the first `template()` is version 1 and its body contains "ASSUMPTION OF RISK".
- `saveTemplateBumpsVersionOnlyWhenChanged`: same body stays v1, a changed body becomes v2.
- `recordSnapshotsTemplate`: record sent, edit the template, and the record keeps the old body and version.
- `statusDerivation`: none / sent / signed, and a signed record beats a later unsigned resend.
- `markReturnedAndClear`.
- `longBodyRendersMultiplePages`: render `String(repeating: "Lorem ipsum dolor sit amet. ", count: 800)`, open it
  with `CGPDFDocument(url as CFURL)`, and expect `numberOfPages > 1`. Also check that page 1's text
  contains "Template v1". Use `PDFKit.PDFDocument(url:)?.page(at: 0)?.string`; PDFKit is available to
  the test target.
- `rendererSkipsCommentLinesAndStripsMarkers`: the rendered text contains no `#` or `!!`.
- `deletingClientDeletesWaiverRecords`.
- `waiversRoundTripThroughArchive`: covers the template and records.

**Update**:
- `SchemaTests`: 12 models and 12 entities.
- `MigrationTests`: assert the `WaiverTemplate` and `WaiverRecord` fetches are empty.
- `SafeImporterTests` and `ArchiveRoundTripTests` stay green.

### Verification
#### Automated
- [x] Test command passes, including the 9 `WaiverTests`.
#### Manual
- [ ] Settings → Liability waiver template: edit and save, and the header shows v2. The notice is
  visible.
- [ ] Client → Send waiver…: the share sheet opens. Save to Files and confirm the PDF has several
  pages, the client name, the bold release paragraphs and "Template v2" in the footer. Status changes
  to "Sent <today>".
- [ ] Open the share sheet again and cancel it. No new record is added.
- [ ] Mark signed & returned with a past date, and the status shows "Signed — returned <date>".

---

## Phase 5: Guided intake flow and finalisation

### Changes

#### 1. Flow view model
**File**: `Sources/Features/Intake/IntakeFlowViewModel.swift`
**Action**: create
```swift
enum IntakeStep: Int, CaseIterable, Identifiable {
    case sections, profile, health, waiver, measurements, movement, review
    var id: Int { rawValue }
    var title: String { ... }   // "Choose sections", "Profile", "Health screening", "Waiver", "Measurements", "Movement", "Review"
}

struct IntakeSections: OptionSet, Sendable {   // not persisted
    let rawValue: Int
    static let health = IntakeSections(rawValue: 1 << 0)
    static let waiver = IntakeSections(rawValue: 1 << 1)
    static let measurements = IntakeSections(rawValue: 1 << 2)
    static let overheadSquat = IntakeSections(rawValue: 1 << 3)
    static let singleLegSquat = IntakeSections(rawValue: 1 << 4)
    static let all: IntakeSections = [.health, .waiver, .measurements, .overheadSquat, .singleLegSquat]
}

@MainActor @Observable
final class IntakeFlowViewModel {
    let client: ClientDTO
    var sections: IntakeSections = .all { didSet { assessment.sections = assessmentSections } }
    private(set) var index = 0
    let profile: ClientEditViewModel
    let health: HealthScreeningEditViewModel
    let waiver: ClientWaiverViewModel
    let assessment: AssessmentEditViewModel
    var errorMessage: String?

    init(client: ClientDTO, clientRepo: any ClientRepository, intake: IntakeRepositories, weightUnit: Unit)

    /// Pure: profile and review always; the rest follow the toggles.
    static func steps(for s: IntakeSections) -> [IntakeStep]
    var steps: [IntakeStep] { Self.steps(for: sections) }
    var current: IntakeStep { steps[min(index, steps.count - 1)] }
    var isLast: Bool { current == .review }

    /// Saves the current step (if it has a draft), then advances. False on save failure.
    func next() async -> Bool
    func back()
    /// True when any step's draft differs from what is stored.
    var hasUnsavedEdits: Bool
}
```
- **`steps(for:)`**:
  - Always `.sections` and `.profile`.
  - Then `.health` and `.waiver` if those are toggled on.
  - `.measurements` if measurements is on.
  - `.movement` if overheadSquat or singleLegSquat is on.
  - `.review` last.
- **`next()`**:
  - Calls `profile.save()` on `.profile`, `health.save()` on `.health`, and `assessment.save()` on
    both `.measurements` and `.movement`. The assessment keeps a stable id, so the second save updates
    the same row.
  - The other steps save nothing.
  - On failure it copies the step view model's `errorMessage` and does not advance.
- **Unsaved-edit tracking**:
  - Each step's view model gets `var isDirty: Bool`. It compares `makeDTO()` (with timestamps forced
    to `.distantPast`) to a baseline captured at init and refreshed after each successful save.
  - Add `isDirty` to `ClientEditViewModel`, `HealthScreeningEditViewModel` and
    `AssessmentEditViewModel`.
  - `hasUnsavedEdits` is the OR of the step view models' `isDirty` for steps in `steps`.
- **Assessment sections**: `assessmentSections` maps `IntakeSections` to `AssessmentSections`.

#### 2. Flow view
**File**: `Sources/Features/Intake/IntakeFlowView.swift`
**Action**: create. A sheet: `NavigationStack { Form { stepContent } }`.
- Navigation title: `"\(step.title) (\(index+1)/\(steps.count))"`.
- `ProgressView(value:)` at the top of the form.
- Step content:
  - **`.sections`**: toggles for Health screening, Waiver, Measurements, Overhead Squat and Single
    Leg Squat, bound to `sections` through `Binding(get:set:)`. Footer: "Profile is always included.
    Each part can be filled in later from the client's page."
  - **`.profile`**: `ClientFormContent(viewModel: vm.profile)`.
  - **`.health`**: `HealthScreeningFormContent(viewModel: vm.health)`.
  - **`.waiver`**: the `ClientWaiverSection` view model content. Footer: "Send now, or skip and send
    later from the client's page."
  - **`.measurements`**: `MeasurementsFormContent(viewModel: vm.assessment)`.
  - **`.movement`**: `MovementFormContent(viewModel: vm.assessment)`.
  - **`.review`**:
    - a summary as `LabeledContent` rows: profile complete yes/no, `ClearanceBadge`, waiver status,
      and the assessment sections recorded
    - a NavigationLink "View assessment" to `AssessmentDetailView` when saved
- `ErrorBanner(message: vm.errorMessage)` is the last section.
- Toolbar:
  - leading: "Cancel", or "Back" when `index > 0` (with Cancel moved into a menu)
  - trailing: "Next" (`.borderedProminent`), or "Done" on review, which dismisses and calls
    `onFinished()`
- `.interactiveDismissDisabled(vm.hasUnsavedEdits)`.
- Cancel asks for confirmation when `hasUnsavedEdits`: a `confirmationDialog` titled "Discard unsaved
  changes?" with "Discard" (destructive) and "Keep editing". Steps already saved stay saved; say so in
  the dialog message.
- **`.onDisappear`**: `WaiverPDFRenderer.removeAll()`.

#### 3. Entry points
**File**: `Sources/Features/Clients/ClientListView.swift`
- Add `@State private var pendingIntake: ClientDTO?` and `@State private var intakeClient: ClientDTO?`.
- Give `ClientEditView` an `onCreated: ((ClientDTO) -> Void)? = nil` parameter, called after a save
  when the client is new (`!viewModel.isEditing`) and not `isSelf`, with `viewModel.savedClient`.
- The Add sheet passes `onCreated: { pendingIntake = $0 }`.
- Add `.sheet(isPresented: $showingAdd, onDismiss: { if pendingIntake != nil { showingIntakeOffer = true } })`.
- Add `.alert("Start intake for \(name)?", isPresented: $showingIntakeOffer)` with:
  - "Start intake", which sets `intakeClient = pendingIntake`
  - "Later"
  - Both clear `pendingIntake`.
- Add `.sheet(item: $intakeClient) { IntakeFlowView(viewModel: IntakeFlowViewModel(client: $0, clientRepo: viewModel.repository, intake: viewModel.intake, weightUnit: unit)) { Task { await viewModel.load() } }`.
  Read `unit` from `@AppStorage("defaultWeightUnit")`.

**File**: `ClientDetailView`
- Add `Button("Start intake", systemImage: "list.bullet.clipboard")` to the toolbar menu. It presents
  the same flow sheet and reloads on finish.
- Hide it for `isSelf`.

#### 4. Freeze contracts
**File**: `Tests/Fixtures/export-v2.json`
**Action**: create, by hand, with stable readable UUIDs in the `export-v1.json` style. Contents:
- `schemaVersion: 2`
- 1 client with every profile field
- 1 exercise
- 0 workouts and 0 sessions
- 1 health screening with answers `32` (boneJointSoftTissue) and a clearance date
- 1 assessment with measurements and one OHS anterior right compensation (`2`)
- a waiver template at version 2
- 1 waiver record with a returned date

Generate a draft from `exportData()` in a scratch test if that helps, then hand-edit it to stable
values. After that it is never regenerated.

**File**: `Tests/ArchiveRoundTripTests.swift`
- Add `goldenV2FixtureImports`, with the same comment block as V1 ("Never regenerate it"). It asserts
  that every entity decoded with the expected values:
  - client DOB and emergency contact
  - `clearance(for:) == .received(...)`
  - assessment `ohsAnteriorRight == [.kneeMovesInward]`
  - template version 2
  - waiver status `.signed`

**File**: `Sources/Services/Archive/ArchiveV2.swift`
- Change the header to: "FROZEN once shipped — never edit after release. Golden fixture:
  Tests/Fixtures/export-v2.json."

**File**: `Sources/Persistence/SchemaV3.swift`
- Change the header to: "Current schema … frozen at release: the next change copies these classes
  into SchemaV3 as nested types (see SchemaV2) and adds SchemaV4."

#### 5. Tests
**File**: `Tests/IntakeFlowViewModelTests.swift`
**Action**: create. Use an in-memory env with `IntakeRepositories(container:)`.
- `stepsFollowSections`: `.all` gives all 7 steps; `[]` gives sections, profile and review; only
  overheadSquat gives sections, profile, movement and review.
- `nextSavesProfileThenHealth`: edit the profile occupation and call `next()` past sections and
  profile; the repository has the occupation. Answer one YES and call `next()`; `latest` is non-nil
  with that answer.
- `measurementsAndMovementSaveOneAssessment`: two `next()` calls produce exactly one assessment row
  holding both.
- `unsavedEditsFlag`: false at start, true after a field edit, false after `next()` saves it.
- `failedSaveDoesNotAdvance`: use a stub `HealthScreeningRepository` that throws; the index stays put
  and `errorMessage` is set.

#### 6. Docs
- **`PRD.md` §4.4**:
  - Replace "Health/PAR-Q intake is deferred with billing" with a short description of the shipped
    intake: profile, screening with clearance, NASM page-1 assessments, and the send/mark waiver.
  - Note that the screening uses the app's own wording, is not PAR-Q+, and is not diagnostic.
- **`PRD.md` §10**: add "Intake health data is stored in the on-device SwiftData store under iOS
  default Data Protection (complete until first unlock), behind the Face ID app lock; waiver PDFs are
  temporary files with complete protection, deleted after sharing."
- **`BACKLOG.md`**:
  - Add a Done row for this work, linking `thoughts/qrspi/2026-11-01-nasm-movement-assessment/`.
  - Add follow-up rows:
    - NASM page 2 assessments (blocked on the form page)
    - charts of assessment measurements over time
    - in-app e-signature
    - compensation → muscle suggestions
- **Repo root**: move `IMG_4699.jpeg` out of the root. A copy already lives in the artifact
  directory as `nasm-assessment-form-p1.jpeg`, so delete the root copy with `git rm` if it is
  tracked, or `rm` if untracked. Confirm with the user first if unsure.

### Verification
#### Automated
- [x] Test command passes. `IntakeFlowViewModelTests` (5) and `goldenV2FixtureImports` pass, and
  `goldenV1FixtureImports` still passes.
- [x] `grep -rn "SchemaV2.versionString\|ArchiveV1.schemaVersion" Sources` finds no live call sites
  except inside `ArchiveV1.swift` and `SchemaV2.swift`.
#### Manual
- [ ] Simulator: add a client, accept "Start intake", and step through every section. Cancel midway
  with edits and get the confirmation; earlier steps stay saved.
- [ ] With only Overhead Squat toggled on, the flow shows sections → profile → movement → review.
- [ ] Device pass on "madphone", using the commands in memory `trainme-build-env-gaps`. Install over
  the existing build with real data, then check:
  - the app opens, so the V2→V3 migration ran
  - existing clients and sessions are intact
  - a full intake works
  - a session shows the clearance warning
  - the waiver shares to Mail
