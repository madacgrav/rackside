import Foundation
import Testing
@testable import TrainMe

private struct Repos {
    let sessions: SwiftDataSessionRepository
    let workouts: SwiftDataWorkoutRepository
}

private func makeRepos() throws -> Repos {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Repos(
        sessions: SwiftDataSessionRepository(modelContainer: container),
        workouts: SwiftDataWorkoutRepository(modelContainer: container)
    )
}

private func sessionDTO(clientId: UUID = UUID(), startAt: Date = .now) -> SessionDTO {
    SessionDTO(
        id: UUID(), clientId: clientId, startAt: startAt,
        endAt: startAt.addingTimeInterval(3600), status: .scheduled,
        notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
}

@Test func schedulingCopiesTemplateIntoInstance() async throws {
    let repos = try makeRepos()
    let exerciseId = UUID()
    let template = WorkoutDTO(
        id: UUID(), name: "Leg Day A",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await repos.workouts.upsert(template)

    let dto = sessionDTO()
    try await repos.sessions.schedule(dto, attaching: [template.id])

    let fetched = try await repos.sessions.get(id: dto.id)
    #expect(fetched?.instances.count == 1)
    #expect(fetched?.instances.first?.name == "Leg Day A")
    #expect(fetched?.instances.first?.sourceWorkoutId == template.id)
    #expect(fetched?.instances.first?.plannedEntries.first?.targetWeight == 185)

    // Edit the template afterward — the scheduled instance must be untouched.
    var edited = template
    edited.name = "Leg Day A v2"
    edited.entries[0].targetWeight = 225
    try await repos.workouts.upsert(edited)

    let after = try await repos.sessions.get(id: dto.id)
    #expect(after?.instances.first?.name == "Leg Day A")
    #expect(after?.instances.first?.plannedEntries.first?.targetWeight == 185)
}

@Test func statusTransitionPersists() async throws {
    let repos = try makeRepos()
    let dto = sessionDTO()
    try await repos.sessions.schedule(dto, attaching: [])

    try await repos.sessions.setStatus(id: dto.id, .completed)
    #expect(try await repos.sessions.get(id: dto.id)?.status == .completed)

    try await repos.sessions.setStatus(id: dto.id, .noShow)
    #expect(try await repos.sessions.get(id: dto.id)?.status == .noShow)
}

@Test func seriesSchedulingSharesSeriesIdAndCopiesPerSession() async throws {
    let repos = try makeRepos()
    let template = WorkoutDTO(
        id: UUID(), name: "Push",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: UUID(), order: 0, targetSets: 3, targetReps: 10, targetWeight: nil, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await repos.workouts.upsert(template)

    // Tuesday 7am anchor
    var components = DateComponents(year: 2026, month: 7, day: 14, hour: 7) // a Tuesday
    let start = Calendar.current.date(from: components)!
    let dto = sessionDTO(startAt: start)
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: nil, occurrenceCount: nil)
    try await repos.sessions.scheduleSeries(dto, recurrence: rule, attaching: [template.id], horizonWeeks: 2)

    components.day = 1
    let monthStart = Calendar.current.date(from: components)!
    let all = try await repos.sessions.sessions(from: monthStart, to: start.addingTimeInterval(60 * 60 * 24 * 30))
    #expect(all.count >= 4) // Tue/Thu over ~2 weeks
    let seriesIds = Set(all.map(\.seriesId))
    #expect(seriesIds.count == 1)
    #expect(seriesIds.first != nil)
    #expect(all.allSatisfy { $0.instances.count == 1 })
    // Every occurrence has its own instance copy (distinct instance ids)
    #expect(Set(all.compactMap { $0.instances.first?.id }).count == all.count)
}

@Test func upcomingReturnsOnlyScheduledSorted() async throws {
    let repos = try makeRepos()
    let now = Date.now
    let s1 = sessionDTO(startAt: now.addingTimeInterval(3600))
    let s2 = sessionDTO(startAt: now.addingTimeInterval(7200))
    let s3 = sessionDTO(startAt: now.addingTimeInterval(10800))
    for s in [s1, s2, s3] {
        try await repos.sessions.schedule(s, attaching: [])
    }
    try await repos.sessions.setStatus(id: s2.id, .cancelled)

    let upcoming = try await repos.sessions.upcoming(after: now, limit: 10)
    #expect(upcoming.map(\.id) == [s1.id, s3.id])
}

@Test func seriesHorizonCoversExactlyNWeeks() async throws {
    let repos = try makeRepos()
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 7))! // Tuesday
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3], endDate: nil, occurrenceCount: nil)

    let series = try await repos.sessions.scheduleSeries(sessionDTO(startAt: start), recurrence: rule, attaching: [], horizonWeeks: 2)

    // "For 2 weeks" of Tuesdays is 2 sessions (14, 21), not 3.
    #expect(series.occurrences.count == 2)
    #expect(series.occurrences.first == start)
    let stored = try await repos.sessions.sessions(from: start, to: start.addingTimeInterval(60 * 60 * 24 * 60))
    #expect(stored.map(\.startAt) == series.occurrences)
    #expect(stored.allSatisfy { $0.seriesId == series.seriesId })
}

@Test func seriesStartingOffRuleWeekdayAnchorsOnFirstRealOccurrence() async throws {
    let repos = try makeRepos()
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 7))! // Wednesday
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: nil, occurrenceCount: nil)

    let series = try await repos.sessions.scheduleSeries(sessionDTO(startAt: start), recurrence: rule, attaching: [], horizonWeeks: 1)

    // Thu 16 and Tue 21 only: the Wednesday anchor itself is not a session,
    // and the calendar event must be built from these dates, not the anchor.
    #expect(series.occurrences.count == 2)
    #expect(series.occurrences.map { calendar.component(.weekday, from: $0) } == [5, 3])
    #expect(series.occurrences.allSatisfy { $0 > start })
}

@Test func deletingSessionRemovesItsSetRecords() async throws {
    let repos = try makeRepos()
    let exerciseId = UUID()
    let template = WorkoutDTO(
        id: UUID(), name: "Legs",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: nil, targetReps: nil, targetWeight: nil, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await repos.workouts.upsert(template)
    let dto = sessionDTO()
    try await repos.sessions.schedule(dto, attaching: [template.id])
    let instanceId = try await repos.sessions.get(id: dto.id)!.instances.first!.id
    try await repos.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: instanceId, exerciseId: exerciseId,
        setIndex: 0, weight: 185, reps: 5, duration: nil, distance: nil,
        rpe: nil, performedAt: .now, createdAt: .now, updatedAt: .now
    ))

    try await repos.sessions.delete(id: dto.id)

    #expect(try await repos.sessions.get(id: dto.id) == nil)
    #expect(try await repos.sessions.setsFor(instanceId: instanceId).isEmpty)
}

@Test func updateNotesPersists() async throws {
    let repos = try makeRepos()
    let dto = sessionDTO()
    try await repos.sessions.schedule(dto, attaching: [])
    try await repos.sessions.updateNotes(id: dto.id, "Knee felt fine")
    #expect(try await repos.sessions.get(id: dto.id)?.notes == "Knee felt fine")
    try await repos.sessions.updateNotes(id: dto.id, nil)
    #expect(try await repos.sessions.get(id: dto.id)?.notes == nil)
}

@Test func updateChangesTimeNotInstances() async throws {
    let repos = try makeRepos()
    let template = WorkoutDTO(id: UUID(), name: "Push", entries: [
        WorkoutEntryDTO(id: UUID(), exerciseId: UUID(), order: 0, targetSets: 3, targetReps: 8, targetWeight: 100, targetDuration: nil)
    ], createdAt: .now, updatedAt: .now)
    try await repos.workouts.upsert(template)
    let dto = sessionDTO()
    try await repos.sessions.schedule(dto, attaching: [template.id])
    var edited = try #require(try await repos.sessions.get(id: dto.id))
    let instanceIds = edited.instances.map(\.id)
    #expect(instanceIds.count == 1)
    edited.startAt = dto.startAt.addingTimeInterval(7200)
    edited.endAt = edited.startAt.addingTimeInterval(1800)
    edited.notes = "moved"
    try await repos.sessions.update(edited)
    let after = try #require(try await repos.sessions.get(id: dto.id))
    #expect(after.startAt == edited.startAt)
    #expect(after.notes == "moved")
    #expect(after.instances.map(\.id) == instanceIds)
}

@Test func completedCountHonorsSince() async throws {
    let repos = try makeRepos()
    let a = sessionDTO()
    let b = sessionDTO()
    try await repos.sessions.schedule(a, attaching: [])
    try await repos.sessions.schedule(b, attaching: [])
    try await repos.sessions.setStatus(id: a.id, .completed)
    let mid = Date.now
    try await Task.sleep(for: .milliseconds(20))
    try await repos.sessions.setStatus(id: b.id, .completed)
    #expect(try await repos.sessions.completedCount(since: nil) == 2)
    #expect(try await repos.sessions.completedCount(since: mid) == 1)
}

@Test func detachClearsSeriesAndEventOnlyForThatRow() async throws {
    let repos = try makeRepos()
    let start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now.addingTimeInterval(86_400))!
    let rule = AppRecurrence(
        frequency: .weekly, interval: 1,
        weekdays: [Calendar.current.component(.weekday, from: start)],
        endDate: nil, occurrenceCount: nil
    )
    let series = try await repos.sessions.scheduleSeries(
        sessionDTO(startAt: start), recurrence: rule, attaching: [], horizonWeeks: 3
    )
    try await repos.sessions.setEventIdentifierForSeries(series.seriesId, "evt-s")
    let before = try await repos.sessions.sessions(from: .distantPast, to: .distantFuture)

    try await repos.sessions.detach(id: before[1].id)

    let after = try await repos.sessions.sessions(from: .distantPast, to: .distantFuture)
    #expect(after[1].seriesId == nil)
    #expect(after[1].eventIdentifier == nil)
    #expect(after[1].recurrence == rule)
    #expect(after[0].seriesId == series.seriesId && after[0].eventIdentifier == "evt-s")
    #expect(after[2].seriesId == series.seriesId && after[2].eventIdentifier == "evt-s")
}

@Test func seriesOccurrencesReportsLoggedSetsAndBulkWrites() async throws {
    let repos = try makeRepos()
    let exerciseId = UUID()
    let template = WorkoutDTO(
        id: UUID(), name: "Legs",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await repos.workouts.upsert(template)
    let start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now.addingTimeInterval(86_400))!
    let rule = AppRecurrence(
        frequency: .weekly, interval: 1,
        weekdays: [Calendar.current.component(.weekday, from: start)],
        endDate: nil, occurrenceCount: nil
    )
    let series = try await repos.sessions.scheduleSeries(
        sessionDTO(startAt: start), recurrence: rule, attaching: [template.id], horizonWeeks: 3
    )
    let rows = try await repos.sessions.sessions(from: .distantPast, to: .distantFuture)
    let instanceId = try #require(rows[1].instances.first?.id)
    try await repos.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: instanceId, exerciseId: exerciseId, setIndex: 0,
        weight: 185, reps: 5, duration: nil, distance: nil, rpe: nil,
        performedAt: .now, createdAt: .now, updatedAt: .now
    ))

    let following = try await repos.sessions.seriesOccurrences(seriesId: series.seriesId, from: rows[1].startAt)
    #expect(following.map(\.session.id) == [rows[1].id, rows[2].id])
    #expect(following.map(\.hasLoggedSets) == [true, false])

    try await repos.sessions.setStatus(ids: [rows[0].id, rows[2].id], .cancelled)
    try await repos.sessions.delete(ids: [rows[1].id])

    let after = try await repos.sessions.sessions(from: .distantPast, to: .distantFuture)
    #expect(after.map(\.id) == [rows[0].id, rows[2].id])
    #expect(after.allSatisfy { $0.status == .cancelled })
    #expect(try await repos.sessions.setsFor(instanceId: instanceId).isEmpty)
}
