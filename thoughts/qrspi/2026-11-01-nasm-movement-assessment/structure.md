# Structure Outline

## Approach
New-client intake is added as five vertical slices:
1. Profile fields, with the V3 schema and the v2 archive groundwork.
2. Health screening with clearance.
3. NASM movement and measurement assessments.
4. A waiver that is sent and then marked returned.
5. A guided intake flow.

Each slice builds the full stack: `@Model` → DTO → `@ModelActor` repository → `@Observable` view model
→ SwiftUI, plus archive and tests. New records link to clients by `clientId` UUID and are deleted
explicitly when their client is deleted.

**Test command**:
`xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5`

**Schema and archive in a single branch:**
- Phase 1 freezes the current models as `SchemaV2` and creates `SchemaV3` (live models) and
  `ArchiveV2`.
- Phases 2–4 add new `@Model` types to `SchemaV3.models` and new arrays to `ArchiveV2.Envelope`.
  Neither has shipped, so they stay editable until merge.
- Phase 5 writes the golden `export-v2.json` and freezes both.

This keeps every slice vertical and still ships a single V2→V3 migration.

---

## Phase 1: Client profile and schema/archive groundwork
The trainer can enter and view date of birth, emergency contact, physician, occupation, training
history and availability. Existing stores migrate V2→V3, and v1 archives still import.

**Files**:
- `Sources/Models/Client.swift`, `Sources/Models/DTO/ClientDTO.swift`
- `Sources/Persistence/SchemaV2.swift` (frozen copies), new `SchemaV3.swift`, migration plan in
  `SchemaV1.swift`, `PersistenceController.swift`, `TrainMeApp.swift` (backup version key)
- `Sources/Services/Archive/ArchiveV1.swift`, new `ArchiveV2.swift`, `DataArchive.swift`
- `Sources/Features/Clients/ClientEditView(+Model).swift`, `ClientDetailView.swift`, `PreviewFixtures.swift`
- Tests: `SchemaTests.swift`, new `MigrationTests.swift`, `ArchiveRoundTripTests.swift`,
  `ClientRepositoryTests.swift`

**Key changes**:
- `Client` gets new fields, each with a default:
  - `dateOfBirth: Date?`
  - `emergencyName: String?`, `emergencyRelationship: String?`, `emergencyPhoneE164: String?`
  - `physicianName: String?`, `physicianPhoneE164: String?`
  - `occupation: String?`, `trainingHistory: String?`, `availability: String?`
- `ClientDTO` adds the same fields as optionals. They are included in `CodingKeys` (unlike `isSelf`).
- Schemas and migration:
  - `enum SchemaV2: VersionedSchema` holds nested frozen copies.
  - `enum SchemaV3: VersionedSchema { static var models = [...live] }`.
  - The plan is `schemas: [V1, V2, V3]` with stages `.lightweight(V1→V2)` and `.lightweight(V2→V3)`.
- Archive:
  - `ArchiveV2.schemaVersion = 2`.
  - `ArchiveV2.Envelope` starts with the same arrays as V1. `CurrentArchive = ArchiveV2.Envelope`.
  - `ArchiveV2.migrate(_ v1: ArchiveV1.Envelope) -> ArchiveV2.Envelope` is a pure function.
  - `importData` probes the version: 1 decodes through V1 and then `migrate`, 2 decodes directly,
    and anything higher is rejected as `newerThanApp`.
- UI:
  - `ClientEditViewModel` adds `dateOfBirth`, `emergency*` and `physician*` draft fields.
    `canSave` requires an emergency phone that normalizes, if one is entered.
  - `ClientEditView` adds "Profile" and "Emergency contact" sections. `ClientDetailView` adds a
    "Profile" section.

**Verify**:
- The test command passes.
- `MigrationTests.v2StoreOpensAsV3` builds an on-disk V2 store with a client, opens it through the
  plan, and checks the client and its fields (new fields nil).
- `goldenV1FixtureImports` stays green, and a v2 round-trip preserves the profile fields.
- Manual: edit a client's profile in the simulator, then check the detail screen.

---

## Phase 2: Health screening and medical clearance
The trainer records a dated health screening. Any YES shows "Medical clearance recommended" on client
detail and in the session screen until the trainer records a clearance date. A review-due notice
appears after 12 months.

**Files**:
- New `Sources/Models/HealthScreening.swift`, `DTO/HealthScreeningDTO.swift`,
  `Persistence/HealthScreeningRepository.swift`
- New `Features/Health/HealthScreeningEditView(+Model).swift`
- Updated: `ClientDetailView(+Model).swift`, `ClientRepository.swift` (delete cascade),
  `SessionRunView(+Model).swift`, `ScheduleViewModel.swift`, `SchemaV3.swift`, `ArchiveV2.swift`,
  `DataArchive.swift`, `PreviewFixtures.swift`
- New `Tests/HealthScreeningTests.swift`

**Key changes**:
- `struct ScreeningAnswers: OptionSet` (Int): `heartOrBP`, `chestPain`, `dizziness`,
  `chronicCondition`, `chronicMedication`, `boneJoint`, `supervisedOnly`. It provides
  `static let all`, `questions: [(ScreeningAnswers, String)]` (the app's own wording) and `anyYes`.
- `@Model HealthScreening`:
  - `id`, `clientId`, `completedOn`, `answersRaw: Int`
  - `conditions`, `surgeries`, `medications`, `familyHeartHistory: Bool`, `symptoms`
  - lifestyle: `sleepHours: Double?`, `stressLevel: Int?` (1–5), `tobacco: Bool`,
    `alcoholPerWeek: Int?`, `activityLevel`
  - `clearanceReceivedOn: Date?`, `notes`, timestamps
- `enum ClearanceStatus { case notScreened, clear, needed, received(Date) }` and
  `static func clearance(for latest: HealthScreeningDTO?) -> ClearanceStatus` (pure).
- `static func reviewDue(_ latest: HealthScreeningDTO?, now: Date) -> Bool` (12 months).
- `protocol HealthScreeningRepository`: `forClient(_:) -> [DTO]` (newest first), `latest(clientId:)`,
  `upsert`, `delete(id:)`, `deleteAll(clientId:)`.
- `ClientRepository.delete(id:)` also deletes the client's screenings. This repeats the explicit
  SetRecord delete in `SessionRepository.swift:315-323`, and later phases add their types here.
- `ArchiveV2.Envelope.healthScreenings: [HealthScreeningDTO]`, and `migrate` from V1 sets `[]`.
  `deleteAll`/`upsertAll` handle the new type.
- `SessionRunViewModel.clearanceNeeded: Bool` is passed in the same way as `clientInjuries`.

**Verify**:
- The test command passes.
- `HealthScreeningTests` cover the clearance states, review due at 12 months, repository ordering,
  delete cascade with the client, and archive round-trip.
- Manual: answer one YES, see the warning on detail and in a session, record clearance, and see the
  warning clear.

---

## Phase 3: Movement and measurement assessments
The trainer records dated assessments with toggled sections: measurements, Overhead Squat (including
the modified retests) and Single Leg Squat. Detail lists the assessments, and each one shows what
changed since the previous assessment.

**Files**:
- New `Sources/Models/Assessment.swift`, `DTO/AssessmentDTO.swift`, `Persistence/AssessmentRepository.swift`
- New `Features/Assessments/AssessmentEditView(+Model).swift`, `AssessmentDetailView.swift`,
  `CompensationGrid.swift`
- Updated: `ClientDetailView(+Model).swift`, `ClientRepository.swift`, `SchemaV3.swift`,
  `ArchiveV2.swift`, `DataArchive.swift`, `PreviewFixtures.swift`
- New `Tests/AssessmentTests.swift`

**Key changes**:
- Section and measurement types:
  - `struct AssessmentSections: OptionSet { measurements, overheadSquat, singleLegSquat }`.
  - `struct Measurements: Codable, Equatable` with optional `restingHR`, `systolic`, `diastolic`,
    `heightCm`, `weightKg`, `waistCm`, `hipCm`, `bodyFatPct`, `pushUps`, `plankSeconds`.
- Compensation option sets (one per view):
  - `struct OHSAnterior: OptionSet { footTurnsOut, kneeMovesIn, kneeMovesOut }`
  - `struct OHSLateral: OptionSet { excessiveForwardLean, lowBackArches, lowBackRounds, armsFallForward }`
  - `struct OHSPosterior: OptionSet { heelRises, footFlattens, asymmetricWeightShift }`
  - `struct OHSModified: OptionSet { feet, knees, lphc, upper }`, used for the "improved" results of
    the modified tests
  - `struct SLSCompensations: OptionSet { footFlattens, kneeMovesIn, kneeMovesOut, hipHike, hipDrop, inwardTrunkRotation, outwardTrunkRotation }`
- `@Model Assessment` fields:
  - `id`, `clientId`, `performedOn`, `sectionsRaw`, `measurementsData: Data?` (JSON, like `recurrenceData`)
  - Overhead squat: `ohsAnteriorRightRaw`, `ohsAnteriorLeftRaw`, `ohsLateralRaw`,
    `ohsPosteriorRightRaw`, `ohsPosteriorLeftRaw`, `ohsHeelsElevatedRaw`, `ohsArmsDownRaw`, `ohsNotes`
  - Single leg squat: `slsRightRaw`, `slsLeftRaw`, `slsNotes`
  - Timestamps
- `static func diff(_ current: AssessmentDTO, previous: AssessmentDTO?) -> AssessmentDiff` (pure).
  It reports compensations resolved and new, and measurement deltas.
- `protocol AssessmentRepository`: `forClient`, `previous(before:clientId:)`, `upsert`, `delete`,
  `deleteAll(clientId:)`.
- `CompensationGrid` is a reusable row of R/L tinted toggles, following `SessionEditView.swift:126-139`.
- `ArchiveV2.Envelope.assessments`.

**Verify**:
- The test command passes.
- `AssessmentTests` cover option-set round-trip, the diff (resolved, new, deltas, no previous),
  repository ordering, delete cascade, and archive round-trip.
- Manual: two assessments for one client. The second shows the differences, and the editor is usable
  at accessibility text size.

---

## Phase 4: Liability waiver (send and mark returned)
The trainer edits a versioned waiver template in Settings and generates a multi-page unsigned PDF for
a client. They share it via `ShareLink`, which records "sent", and later mark it "Signed — returned on
<date>".

**Files**:
- New `Sources/Models/Waiver.swift` (`WaiverTemplate`, `WaiverRecord`), `DTO/WaiverDTO.swift`,
  `Persistence/WaiverRepository.swift`, `Services/WaiverPDFRenderer.swift`,
  `Resources/waiver_starter.md`
- New `Features/Waiver/WaiverTemplateEditView.swift`, `ClientWaiverSection.swift`
- Updated: `SettingsView.swift`, `ClientDetailView(+Model).swift`, `ClientRepository.swift`,
  `SchemaV3.swift`, `ArchiveV2.swift`, `DataArchive.swift`
- New `Tests/WaiverTests.swift`

**Key changes**:
- `@Model WaiverTemplate { id, version: Int, body: String, updatedAt }`, a single row.
  `WaiverRepository.template()` seeds it from the starter text.
- `WaiverRepository.saveTemplate(body:)` bumps `version` whenever the body changes.
- `@Model WaiverRecord { id, clientId, sentOn, templateVersion, templateBody, returnedSignedOn: Date?, notes }`.
- `WaiverRepository` also provides `records(clientId:)`, `recordSent(clientId:) -> WaiverRecordDTO`,
  `markReturned(id:on:)`, `delete(id:)` and `deleteAll(clientId:)`.
- `enum WaiverStatus { none, sent(Date), signed(Date) }` with
  `static func status(_ records: [WaiverRecordDTO]) -> WaiverStatus`.
- `WaiverPDFRenderer.render(body:clientName:trainerName:version:date:) throws -> URL`:
  - Built on `UIGraphicsPDFRenderer` with paginated `NSAttributedString` layout.
  - Writes to `tmp/Waivers` with `.completeFileProtection`. `removeAll()` sweeps the folder.
- The Settings editor shows a fixed "not legal advice — have your attorney or insurer review"
  notice.
- `ArchiveV2.Envelope.waiverTemplate: WaiverTemplateDTO?` and `waivers: [WaiverRecordDTO]`.

**Verify**:
- The test command passes.
- `WaiverTests` cover:
  - the version bumps only when the body changes
  - the snapshot is kept after a template edit
  - status derivation
  - a long body renders more than one PDF page (`CGPDFDocument.numberOfPages`), with the version
    present in the text
  - archive round-trip and delete cascade
- Manual: share the waiver to Files or Mail, mark it returned, and check the detail status.

---

## Phase 5: Guided intake flow and finalisation
"Start intake" is offered after a new client is saved and is also available from client detail. A
step sheet walks through:
1. Section toggles
2. Profile
3. Health
4. Waiver
5. Measurements
6. Movement
7. Review

Each step saves on Next, and Cancel asks for confirmation if there are unsaved edits.

Then freeze the archive and schema, check the store's file protection, and update the docs.

**Files**:
- New `Features/Intake/IntakeFlowView.swift`, `IntakeFlowViewModel.swift`
- Updated: `ClientListView.swift` (offer after create), `ClientDetailView.swift`
- New `Tests/Fixtures/export-v2.json`, `Tests/IntakeFlowViewModelTests.swift`, `ArchiveRoundTripTests.swift`
- `PersistenceController.swift` (file-protection review)
- `PRD.md` §4.4, `BACKLOG.md`

**Key changes**:
- `enum IntakeStep: CaseIterable { sections, profile, health, waiver, measurements, movement, review }`.
- `IntakeFlowViewModel`:
  - `steps: [IntakeStep]`, filtered by the chosen sections
  - `next() async -> Bool`, which saves the current step
  - `back()`, `hasUnsavedEdits`
- The step views reuse the phase 1–4 editors' content views. The reusable `Form` content is extracted
  from each edit sheet so that the sheet and the flow share it.
- `goldenV2FixtureImports` is the new frozen contract. The `ArchiveV2` and `SchemaV3` header comments
  mark them frozen.

**Verify**:
- The test command passes.
- `IntakeFlowViewModelTests` cover step filtering, save-on-next, and the unsaved-edits flag.
- Both golden fixtures import.
- Manual device pass on "madphone": create a client, run the full intake, check every detail section
  and the session warning, and confirm an existing store migrated.

---

## Testing Checkpoints
- **After Phase 1**:
  - V3 schema plus a real V2→V3 migration test.
  - Archive v2 envelope with a v1 migrate.
  - Profile fields are editable and shown.
  - All existing tests pass.
- **After Phase 2**: screenings persist, export and cascade. The clearance warning shows on detail and
  in the session.
- **After Phase 3**: assessments with toggled sections and a diff against the previous one. The
  option sets round-trip.
- **After Phase 4**:
  - Versioned waiver template and record snapshots.
  - Multi-page PDF shared via `ShareLink`.
  - Marked-returned status.
- **After Phase 5**:
  - Guided intake works end to end.
  - Golden `export-v2.json` and the frozen V3/ArchiveV2 contracts.
  - File-protection review done, and docs updated.
