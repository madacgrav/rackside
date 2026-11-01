import Foundation
import Observation

@MainActor
@Observable
final class SessionRunViewModel {
    let sessionRepo: any SessionRepository
    let exerciseRepo: any ExerciseRepository
    let clientRepo: any ClientRepository
    private let calendar: any CalendarSyncing
    /// Called after a status change so the presenting screen can refresh its
    /// list and re-plan trainer alerts (a cancelled session must stop alerting).
    private let onStatusChanged: @MainActor () async -> Void
    var session: SessionDTO
    var clientName: String
    var clientPhone: String?
    /// Surfaced at the top of the run screen so the trainer trains safely (PRD §4.4).
    var clientInjuries: String?
    var notesDraft: String
    var exercises: [UUID: ExerciseDTO] = [:]
    var recordedSets: [UUID: [SetRecordDTO]] = [:]  // keyed by instance id
    /// Set when a mutation fails; rendered at the top of the run screen.
    var errorMessage: String?
    /// Set when the store change succeeded but the calendar step did not.
    var calendarWarning: String?
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
            total + instance.plannedEntries.reduce(0) {
                $0 + min(sets(instanceId: instance.id, exerciseId: $1.exerciseId).count, max($1.targetSets ?? 1, 1))
            }
        }
    }

    var progress: Double { plannedSetCount == 0 ? 0 : Double(loggedSetCount) / Double(plannedSetCount) }

    /// Part of a repeating series. Editing one occurrence detaches it first
    /// (`SeriesActions.detach`); cancel and delete touch only its calendar date.
    var isSeries: Bool { session.seriesId != nil }

    private var series: SeriesActions { SeriesActions(sessionRepo: sessionRepo, calendar: calendar) }

    init(
        sessionRepo: any SessionRepository,
        exerciseRepo: any ExerciseRepository,
        clientRepo: any ClientRepository,
        calendar: any CalendarSyncing = EventKitCalendarService(),
        session: SessionDTO,
        clientName: String,
        clientPhone: String? = nil,
        clientInjuries: String? = nil,
        onStatusChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.sessionRepo = sessionRepo
        self.exerciseRepo = exerciseRepo
        self.clientRepo = clientRepo
        self.calendar = calendar
        self.session = session
        self.clientName = clientName
        self.clientPhone = clientPhone
        self.clientInjuries = clientInjuries
        self.notesDraft = session.notes ?? ""
        self.onStatusChanged = onStatusChanged
    }

    func load() async {
        do {
            let all = try await exerciseRepo.all()
            exercises = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        } catch {
            Log.ui.debug("exercise list load failed: \(error.localizedDescription)")
        }
        for instance in session.instances {
            recordedSets[instance.id] = await loadSets(instanceId: instance.id) ?? []
        }
        let exerciseIds = Set(session.instances.flatMap(\.plannedEntries).map(\.exerciseId))
        for id in exerciseIds {
            if let last = await lastSet(exerciseId: id) { previousSets[id] = last }
        }
        await refreshSession()
    }

    /// Refreshes after the edit sheet saves and lets the presenter reload and
    /// re-plan trainer alerts.
    func reloadAfterEdit() async {
        await refreshSession()
        await onStatusChanged()
    }

    /// Removes the session (the repository deletes its set records) and its
    /// calendar event, then lets the presenter reload and re-plan alerts.
    /// Returns false (with `errorMessage` set) when the store delete failed;
    /// the presenter should not dismiss in that case.
    func delete() async -> Bool {
        errorMessage = nil
        calendarWarning = nil
        if session.seriesId != nil {
            // Store first, then drop just this date from the shared event.
            do {
                calendarWarning = try await series.deleteOccurrence(session).calendarWarning
            } catch {
                Log.ui.error("delete session failed: \(error.localizedDescription)")
                errorMessage = "Couldn't delete the session. Please try again."
                return false
            }
            await onStatusChanged()
            return true
        }
        if let eventId = session.eventIdentifier {
            do {
                try await calendar.remove(eventIdentifier: eventId)
            } catch {
                // Non-blocking: a stale calendar entry is recoverable, a stuck session is not.
                Log.calendar.error("remove on delete failed: \(error.localizedDescription)")
            }
        }
        do {
            try await sessionRepo.delete(id: session.id)
        } catch {
            Log.ui.error("delete session failed: \(error.localizedDescription)")
            errorMessage = "Couldn't delete the session. Please try again."
            return false
        }
        await onStatusChanged()
        return true
    }

    func saveNotes() async {
        errorMessage = nil
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await sessionRepo.updateNotes(id: session.id, trimmed.isEmpty ? nil : trimmed)
        } catch {
            // Keep the draft so the trainer's typing is not lost.
            Log.ui.error("updateNotes failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save notes."
            return
        }
        await refreshSession()
    }

    func sets(instanceId: UUID, exerciseId: UUID) -> [SetRecordDTO] {
        (recordedSets[instanceId] ?? []).filter { $0.exerciseId == exerciseId }
    }

    func record(instanceId: UUID, exerciseId: UUID, weight: Double?, reps: Int?, duration: Int?, distance: Double?) async {
        let nextIndex = (sets(instanceId: instanceId, exerciseId: exerciseId).map(\.setIndex).max() ?? -1) + 1
        let dto = SetRecordDTO(
            id: UUID(),
            workoutInstanceId: instanceId,
            exerciseId: exerciseId,
            setIndex: nextIndex,
            weight: weight,
            reps: reps,
            duration: duration,
            distance: distance,
            rpe: nil,
            performedAt: .now,
            createdAt: .now,
            updatedAt: .now
        )
        errorMessage = nil
        do {
            try await sessionRepo.recordSet(dto)
        } catch {
            Log.ui.error("recordSet failed: \(error.localizedDescription)")
            errorMessage = "Couldn't log that set."
            return
        }
        if let sets = await loadSets(instanceId: instanceId) {
            recordedSets[instanceId] = sets
        }
    }

    /// Logs a draft from the inline set table, keeping only the metrics the
    /// exercise tracks.
    func record(draft: SetDraft, instanceId: UUID, exerciseId: UUID) async {
        let metrics = exercises[exerciseId]?.metrics ?? [.weight, .reps]
        await record(
            instanceId: instanceId,
            exerciseId: exerciseId,
            weight: metrics.contains(.weight) ? draft.weight : nil,
            reps: metrics.contains(.reps) ? draft.reps : nil,
            duration: metrics.contains(.duration) ? draft.duration : nil,
            distance: metrics.contains(.distance) ? draft.distance.flatMap { $0 > 0 ? $0 : nil } : nil
        )
        if errorMessage == nil { lastLoggedSetId = UUID() }
    }

    func deleteSet(_ record: SetRecordDTO) async {
        errorMessage = nil
        do {
            try await sessionRepo.deleteSet(id: record.id)
        } catch {
            Log.ui.error("deleteSet failed: \(error.localizedDescription)")
            errorMessage = "Couldn't delete that set."
            return
        }
        if let sets = await loadSets(instanceId: record.workoutInstanceId) {
            recordedSets[record.workoutInstanceId] = sets
        }
    }

    func lastSet(exerciseId: UUID) async -> SetRecordDTO? {
        do {
            return try await sessionRepo.lastSet(clientId: session.clientId, exerciseId: exerciseId)
        } catch {
            Log.ui.debug("lastSet failed: \(error.localizedDescription)")
            return nil
        }
    }

    func setStatus(_ status: SessionStatus) async {
        errorMessage = nil
        calendarWarning = nil
        do {
            if status == .cancelled, session.seriesId != nil {
                calendarWarning = try await series.cancelOccurrence(session).calendarWarning
            } else {
                try await sessionRepo.setStatus(id: session.id, status)
            }
        } catch {
            Log.ui.error("setStatus failed: \(error.localizedDescription)")
            errorMessage = "Couldn't update the session status."
            return
        }
        // Cancelled sessions leave the system calendar (one-way push cleanup).
        // Series occurrences were handled above by removing just their date.
        if status == .cancelled, session.seriesId == nil, let eventId = session.eventIdentifier {
            do {
                try await calendar.remove(eventIdentifier: eventId)
                try await sessionRepo.setEventIdentifier(id: session.id, nil)
            } catch {
                // Keep the identifier so a later cancel/delete can retry the removal.
                Log.calendar.error("cancel cleanup failed: \(error.localizedDescription)")
            }
        }
        await refreshSession()
        await onStatusChanged()
    }

    // MARK: - Private

    /// Re-reads the session; a read failure keeps the current value.
    private func refreshSession() async {
        do {
            if let refreshed = try await sessionRepo.get(id: session.id) {
                session = refreshed
                notesDraft = session.notes ?? ""
            }
        } catch {
            Log.ui.debug("session refresh failed: \(error.localizedDescription)")
        }
    }

    /// nil on failure so callers can leave the displayed list untouched.
    private func loadSets(instanceId: UUID) async -> [SetRecordDTO]? {
        do {
            return try await sessionRepo.setsFor(instanceId: instanceId)
        } catch {
            Log.ui.debug("setsFor failed: \(error.localizedDescription)")
            return nil
        }
    }
}
