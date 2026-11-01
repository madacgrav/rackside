import Foundation
import SwiftData

protocol SessionRepository: Sendable {
    /// Schedules a session, deep-copying each attached workout template into a
    /// WorkoutInstance (PRD §4.2: instances are frozen copies).
    func schedule(_ dto: SessionDTO, attaching workoutIds: [UUID]) async throws
    /// Materializes a recurring series as individual sessions sharing a seriesId.
    /// `horizonWeeks` is the number of whole weeks covered, counted from the
    /// start: 8 weeks of Tuesdays yields 8 sessions, not 9. Returns the
    /// seriesId and the occurrence dates so callers can push a calendar event
    /// that matches exactly what was scheduled.
    @discardableResult
    func scheduleSeries(
        _ dto: SessionDTO,
        recurrence: AppRecurrence,
        attaching workoutIds: [UUID],
        horizonWeeks: Int
    ) async throws -> ScheduledSeries
    func get(id: UUID) async throws -> SessionDTO?
    func sessions(from: Date, to: Date) async throws -> [SessionDTO]
    func upcoming(after: Date, limit: Int) async throws -> [SessionDTO]
    func forClient(_ clientId: UUID) async throws -> [SessionDTO]
    func setStatus(id: UUID, _ status: SessionStatus) async throws
    /// Updates client, time window and notes. Instances are frozen copies and
    /// are never touched here (PRD §4.2).
    func update(_ dto: SessionDTO) async throws
    func setEventIdentifier(id: UUID, _ eventIdentifier: String?) async throws
    func setEventIdentifierForSeries(_ seriesId: UUID, _ eventIdentifier: String?) async throws
    /// Takes one session out of its series: clears `seriesId` and the shared
    /// event identifier (the caller pushes a standalone event). Keeps
    /// `recurrenceData` as history; nothing reads it for a non-series row.
    func detach(id: UUID) async throws
    func updateNotes(id: UUID, _ notes: String?) async throws
    func delete(id: UUID) async throws
    /// Sessions marked completed after `since` (all of them when nil). Drives
    /// the export-staleness reminder.
    func completedCount(since: Date?) async throws -> Int

    // Recording (Phase 5)
    func recordSet(_ dto: SetRecordDTO) async throws
    func deleteSet(id: UUID) async throws
    func setsFor(instanceId: UUID) async throws -> [SetRecordDTO]
    /// Most recent set this client performed for the exercise, across sessions —
    /// powers "repeat last set".
    func lastSet(clientId: UUID, exerciseId: UUID) async throws -> SetRecordDTO?
}

/// Result of scheduling a recurring series.
struct ScheduledSeries: Sendable, Equatable {
    let seriesId: UUID
    /// Start dates of every session that was created, ascending.
    let occurrences: [Date]
}

/// Expands a recurrence rule into concrete occurrence dates (inclusive of
/// `horizon`). Pure function so scheduling logic is directly unit-testable (no
/// SwiftData involved). Seconds are dropped from `start` so an anchor such as
/// 09:00:30 still produces its own first occurrence at 09:00.
func expandRecurrence(_ rule: AppRecurrence, from rawStart: Date, to horizon: Date) -> [Date] {
    var calendar = Calendar.current
    calendar.firstWeekday = 1 // Sunday, matching EKWeekday numbering
    var dates: [Date] = []
    let maxCount = rule.occurrenceCount ?? Int.max
    let end = rule.endDate.map { min($0, horizon) } ?? horizon
    let timeComponents = calendar.dateComponents([.hour, .minute], from: rawStart)
    let start = calendar.date(
        bySettingHour: timeComponents.hour ?? 0,
        minute: timeComponents.minute ?? 0,
        second: 0,
        of: rawStart
    ) ?? rawStart

    switch rule.frequency {
    case .daily:
        var current = start
        while current <= end, dates.count < maxCount {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: max(1, rule.interval), to: current) else { break }
            current = next
        }
    case .weekly:
        let weekdays = rule.weekdays.isEmpty
            ? [calendar.component(.weekday, from: start)]
            : rule.weekdays.sorted()
        // Walk week by week from the week containing `start`.
        guard var weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start else { return [] }
        outer: while weekStart <= end {
            for weekday in weekdays {
                guard var occurrence = calendar.date(byAdding: .day, value: weekday - 1, to: weekStart) else { continue }
                occurrence = calendar.date(
                    bySettingHour: timeComponents.hour ?? 0,
                    minute: timeComponents.minute ?? 0,
                    second: 0,
                    of: occurrence
                ) ?? occurrence
                if occurrence >= start, occurrence <= end {
                    dates.append(occurrence)
                    if dates.count >= maxCount { break outer }
                }
            }
            guard let next = calendar.date(byAdding: .weekOfYear, value: max(1, rule.interval), to: weekStart) else { break }
            weekStart = next
        }
    }
    return dates
}

@ModelActor
actor SwiftDataSessionRepository: SessionRepository {
    func schedule(_ dto: SessionDTO, attaching workoutIds: [UUID]) async throws {
        try insertSession(dto, attaching: workoutIds)
        try modelContext.save()
    }

    @discardableResult
    func scheduleSeries(
        _ dto: SessionDTO,
        recurrence: AppRecurrence,
        attaching workoutIds: [UUID],
        horizonWeeks: Int = 12
    ) async throws -> ScheduledSeries {
        // Exclusive horizon: N weeks from the start covers exactly N weeks, so
        // the same weekday N weeks later is not included.
        let horizon = Calendar.current
            .date(byAdding: .weekOfYear, value: horizonWeeks, to: dto.startAt)?
            .addingTimeInterval(-1) ?? dto.startAt
        let occurrences = expandRecurrence(recurrence, from: dto.startAt, to: horizon)
        let seriesId = UUID()
        let duration = dto.endAt.timeIntervalSince(dto.startAt)
        let recurrenceData = try? JSONEncoder().encode(recurrence)

        for date in occurrences {
            let occurrence = SessionDTO(
                id: UUID(),
                clientId: dto.clientId,
                startAt: date,
                endAt: date.addingTimeInterval(duration),
                status: .scheduled,
                notes: dto.notes,
                instances: [],
                seriesId: seriesId,
                recurrence: recurrence,
                eventIdentifier: nil,
                createdAt: .now,
                updatedAt: .now
            )
            let model = try insertSession(occurrence, attaching: workoutIds)
            model.recurrenceData = recurrenceData
        }
        try modelContext.save()
        return ScheduledSeries(seriesId: seriesId, occurrences: occurrences)
    }

    func get(id: UUID) async throws -> SessionDTO? {
        try fetch(id: id).map(SessionDTO.init)
    }

    func sessions(from: Date, to: Date) async throws -> [SessionDTO] {
        try modelContext
            .fetch(FetchDescriptor<Session>(
                predicate: #Predicate { $0.startAt >= from && $0.startAt < to },
                sortBy: [SortDescriptor(\.startAt)]
            ))
            .map(SessionDTO.init)
    }

    func upcoming(after: Date, limit: Int) async throws -> [SessionDTO] {
        let scheduledRaw = SessionStatus.scheduled.rawValue
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.startAt > after && $0.statusRaw == scheduledRaw },
            sortBy: [SortDescriptor(\.startAt)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(SessionDTO.init)
    }

    func forClient(_ clientId: UUID) async throws -> [SessionDTO] {
        try modelContext
            .fetch(FetchDescriptor<Session>(
                predicate: #Predicate { $0.clientId == clientId },
                sortBy: [SortDescriptor(\.startAt, order: .reverse)]
            ))
            .map(SessionDTO.init)
    }

    func setStatus(id: UUID, _ status: SessionStatus) async throws {
        guard let session = try fetch(id: id) else { return }
        session.statusRaw = status.rawValue
        session.updatedAt = .now
        try modelContext.save()
    }

    func update(_ dto: SessionDTO) async throws {
        guard let session = try fetch(id: dto.id) else { return }
        session.clientId = dto.clientId
        session.startAt = dto.startAt
        session.endAt = dto.endAt
        session.notes = dto.notes
        session.updatedAt = .now
        try modelContext.save()
    }

    func setEventIdentifier(id: UUID, _ eventIdentifier: String?) async throws {
        guard let session = try fetch(id: id) else { return }
        session.eventIdentifier = eventIdentifier
        session.updatedAt = .now
        try modelContext.save()
    }

    func setEventIdentifierForSeries(_ seriesId: UUID, _ eventIdentifier: String?) async throws {
        let sessions = try modelContext.fetch(
            FetchDescriptor<Session>(predicate: #Predicate { $0.seriesId == seriesId })
        )
        for session in sessions {
            session.eventIdentifier = eventIdentifier
            session.updatedAt = .now
        }
        try modelContext.save()
    }

    func detach(id: UUID) async throws {
        guard let session = try fetch(id: id) else { return }
        session.seriesId = nil
        session.eventIdentifier = nil
        session.updatedAt = .now
        try modelContext.save()
    }

    func updateNotes(id: UUID, _ notes: String?) async throws {
        guard let session = try fetch(id: id) else { return }
        session.notes = notes
        session.updatedAt = .now
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        guard let session = try fetch(id: id) else { return }
        // SetRecords link to instances by id, not by relationship, so the
        // cascade does not reach them; delete them explicitly or they orphan.
        let instanceIds = session.instances.map(\.id)
        if !instanceIds.isEmpty {
            try modelContext.delete(
                model: SetRecord.self,
                where: #Predicate { instanceIds.contains($0.workoutInstanceId) }
            )
        }
        modelContext.delete(session)
        try modelContext.save()
    }

    func completedCount(since: Date?) async throws -> Int {
        let completedRaw = SessionStatus.completed.rawValue
        let floor = since ?? .distantPast
        return try modelContext.fetchCount(FetchDescriptor<Session>(
            predicate: #Predicate { $0.statusRaw == completedRaw && $0.updatedAt > floor }
        ))
    }

    // MARK: - Recording

    func recordSet(_ dto: SetRecordDTO) async throws {
        modelContext.insert(dto.toModel())
        try modelContext.save()
    }

    func deleteSet(id: UUID) async throws {
        guard let record = try modelContext
            .fetch(FetchDescriptor<SetRecord>(predicate: #Predicate { $0.id == id }))
            .first
        else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    func setsFor(instanceId: UUID) async throws -> [SetRecordDTO] {
        try modelContext
            .fetch(FetchDescriptor<SetRecord>(
                predicate: #Predicate { $0.workoutInstanceId == instanceId },
                sortBy: [SortDescriptor(\.exerciseId), SortDescriptor(\.setIndex)]
            ))
            .map(SetRecordDTO.init)
    }

    func lastSet(clientId: UUID, exerciseId: UUID) async throws -> SetRecordDTO? {
        let clientSessions = try modelContext.fetch(
            FetchDescriptor<Session>(predicate: #Predicate { $0.clientId == clientId })
        )
        let instanceIds = clientSessions.flatMap { $0.instances.map(\.id) }
        guard !instanceIds.isEmpty else { return nil }

        var descriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { instanceIds.contains($0.workoutInstanceId) && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(SetRecordDTO.init)
    }

    // MARK: - Private

    @discardableResult
    private func insertSession(_ dto: SessionDTO, attaching workoutIds: [UUID]) throws -> Session {
        let session = Session(
            id: dto.id,
            clientId: dto.clientId,
            startAt: dto.startAt,
            endAt: dto.endAt,
            status: dto.status,
            notes: dto.notes,
            seriesId: dto.seriesId,
            recurrenceData: dto.recurrence.flatMap { try? JSONEncoder().encode($0) },
            eventIdentifier: dto.eventIdentifier,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        modelContext.insert(session)

        for workoutId in workoutIds {
            guard let template = try fetchWorkout(id: workoutId) else { continue }
            // COPY the template: the instance is frozen at scheduling time.
            let instance = WorkoutInstance(id: UUID(), sourceWorkoutId: template.id, name: template.name)
            session.instances.append(instance)
            let copied = template.entries
                .sorted { $0.order < $1.order }
                .map { entry in
                    PlannedEntry(
                        id: UUID(),
                        exerciseId: entry.exerciseId,
                        order: entry.order,
                        targetSets: entry.targetSets,
                        targetReps: entry.targetReps,
                        targetWeight: entry.targetWeight,
                        targetDuration: entry.targetDuration
                    )
                }
            instance.plannedEntries.append(contentsOf: copied)
        }
        return session
    }

    private func fetch(id: UUID) throws -> Session? {
        try modelContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchWorkout(id: UUID) throws -> Workout? {
        try modelContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first
    }
}
