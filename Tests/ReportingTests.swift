import Foundation
import Testing
@testable import Rackside

private struct Env {
    let sessions: SwiftDataSessionRepository
    let workouts: SwiftDataWorkoutRepository
    let exercises: SwiftDataExerciseRepository
    let reporting: SwiftDataReportingQueries
    let clientId = UUID()
    let exerciseId = UUID()
}

private func makeEnv() throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Env(
        sessions: SwiftDataSessionRepository(modelContainer: container),
        workouts: SwiftDataWorkoutRepository(modelContainer: container),
        exercises: SwiftDataExerciseRepository(modelContainer: container),
        reporting: SwiftDataReportingQueries(modelContainer: container)
    )
}

/// Schedules a session with one instance, records the given sets, applies the status.
/// Returns the session id.
@discardableResult
private func addSession(
    _ env: Env,
    start: Date,
    sets: [(weight: Double?, reps: Int?)],
    status: SessionStatus,
    exerciseId: UUID? = nil
) async throws -> UUID {
    let exerciseId = exerciseId ?? env.exerciseId
    let template = WorkoutDTO(
        id: UUID(), name: "W",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: nil, targetReps: nil, targetWeight: nil, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await env.workouts.upsert(template)
    let dto = SessionDTO(
        id: UUID(), clientId: env.clientId, startAt: start,
        endAt: start.addingTimeInterval(3600), status: .scheduled,
        notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await env.sessions.schedule(dto, attaching: [template.id])
    let instanceId = try await env.sessions.get(id: dto.id)!.instances.first!.id
    for (index, set) in sets.enumerated() {
        try await env.sessions.recordSet(SetRecordDTO(
            id: UUID(), workoutInstanceId: instanceId, exerciseId: exerciseId,
            setIndex: index, weight: set.weight, reps: set.reps, duration: nil, distance: nil,
            rpe: nil, performedAt: start.addingTimeInterval(Double(index) * 60),
            createdAt: .now, updatedAt: .now
        ))
    }
    try await env.sessions.setStatus(id: dto.id, status)
    return dto.id
}

private func makeExercise(_ env: Env, name: String, unit: Rackside.Unit) async throws -> UUID {
    try await env.exercises.create(ExerciseDTO(
        id: UUID(), name: name, category: .strength, metrics: [.weight, .reps, .sets],
        defaultUnit: unit, isCustom: true, createdAt: .now, updatedAt: .now
    )).id
}

/// A fixed Wednesday 07:00 `weeksAgo` weeks back, so week grouping never straddles a boundary.
private func midWeek(weeksAgo: Int) -> Date {
    let calendar = Calendar.current
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
    let week = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)!
    return calendar.date(byAdding: DateComponents(day: 3, hour: 7), to: week)!
}

private func daysAgo(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: .now)!
}

/// One-set convenience used by the original tests.
@discardableResult
private func addSession(
    _ env: Env, daysAgo days: Int, weight: Double?, reps: Int? = 5, status: SessionStatus
) async throws -> UUID {
    try await addSession(env, start: daysAgo(days), sets: [(weight, reps)], status: status)
}

@Test func progressionExcludesCancelledAndNoShow() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 21, weight: 185, status: .completed)
    try await addSession(env, daysAgo: 14, weight: 500, status: .cancelled)
    try await addSession(env, daysAgo: 10, weight: 400, status: .noShow)
    try await addSession(env, daysAgo: 7, weight: 195, status: .completed)

    let points = try await env.reporting.progression(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(points.count == 2)
    #expect(points.compactMap(\.topSetWeight) == [185, 195])
}

@Test func personalBestIsHeaviestCompletedSet() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 21, weight: 185, status: .completed)
    try await addSession(env, daysAgo: 14, weight: 225, status: .completed)
    try await addSession(env, daysAgo: 7, weight: 205, status: .completed)
    try await addSession(env, daysAgo: 3, weight: 315, status: .cancelled) // must not count

    let pb = try await env.reporting.personalBest(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(pb?.weight == 225)
}

@Test func epleyFormula() {
    #expect(epley1RM(weight: 300, reps: 0) == 300)
    #expect(epley1RM(weight: 300, reps: nil) == 300)
    #expect(abs(epley1RM(weight: 200, reps: 5) - 233.333) < 0.01)
    #expect(abs(epley1RM(weight: 100, reps: 10) - 133.333) < 0.01)
}

@Test func sparseDataDetectable() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 7, weight: 185, status: .completed)

    let points = try await env.reporting.progression(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(points.count == 1)
    #expect(points.count < 2) // the UI's "not enough data yet" threshold
}

@Test func exercisesWithDataOnlyListsCompleted() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 7, weight: 185, status: .cancelled)
    #expect(try await env.reporting.exercisesWithData(clientId: env.clientId).isEmpty)

    try await addSession(env, daysAgo: 3, weight: 185, status: .completed)
    #expect(try await env.reporting.exercisesWithData(clientId: env.clientId) == [env.exerciseId])
}

@Test func totalRepsSumsAcrossSets() async throws {
    let env = try makeEnv()
    try await addSession(env, start: daysAgo(7), sets: [(185, 5), (185, 5), (190, 3)], status: .completed)

    let points = try await env.reporting.progression(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(points.count == 1)
    #expect(points.first?.totalReps == 13)
    #expect(points.first?.topSetWeight == 190)
}

@Test func repsOnlySetsProduceRepsPointWithoutWeight() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 7, weight: nil, reps: 20, status: .completed)
    try await addSession(env, daysAgo: 3, weight: nil, reps: 25, status: .completed)

    let points = try await env.reporting.progression(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(points.map(\.totalReps) == [20, 25])
    #expect(points.allSatisfy { $0.topSetWeight == nil && $0.est1RM == nil })
    #expect(points.compactMap(\.totalRepsMetric).count == 2)

    let pb = try await env.reporting.personalBest(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(pb == nil)
}

@Test func historyGroupsBySessionNewestFirst() async throws {
    let env = try makeEnv()
    try await addSession(env, start: daysAgo(10), sets: [(185, 5), (190, 3)], status: .completed)
    try await addSession(env, start: daysAgo(3), sets: [(200, 5)], status: .completed)
    try await addSession(env, start: daysAgo(1), sets: [(300, 1)], status: .cancelled)

    let history = try await env.reporting.historyBySession(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(history.count == 2)
    #expect(history[0].sets.map(\.weight) == [200])
    #expect(history[1].sets.map(\.weight) == [185, 190])
    #expect(history[1].sets.map(\.setIndex) == [0, 1])
}

@Test func historyKeepsTwoSessionsOnOneDayDistinct() async throws {
    let env = try makeEnv()
    let morning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: daysAgo(2))!
    try await addSession(env, start: morning, sets: [(185, 5)], status: .completed)
    try await addSession(env, start: morning.addingTimeInterval(8 * 3600), sets: [(195, 5)], status: .completed)

    let history = try await env.reporting.historyBySession(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(history.count == 2)
    #expect(history.map { $0.sets.first?.weight } == [195, 185])

    let points = try await env.reporting.progression(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(points.count == 1) // progression still merges by day
}

@Test func consistencyRateCountsResolvedOnly() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 20, weight: 100, status: .completed)
    try await addSession(env, daysAgo: 15, weight: 100, status: .completed)
    try await addSession(env, daysAgo: 10, weight: 100, status: .completed)
    try await addSession(env, daysAgo: 8, weight: 100, status: .cancelled)
    try await addSession(env, daysAgo: 5, weight: 100, status: .scheduled) // forgotten

    let c = try await env.reporting.consistency(clientId: env.clientId, from: nil, to: .now)
    #expect(c == ConsistencySummary(completed: 3, cancelled: 1, noShow: 0, unresolved: 1))
    #expect(c.rate == 0.75)
}

@Test func consistencyIgnoresFutureScheduled() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 3, weight: 100, status: .noShow)
    try await addSession(env, daysAgo: -3, weight: 100, status: .scheduled) // upcoming

    let c = try await env.reporting.consistency(clientId: env.clientId, from: nil, to: .now)
    #expect(c.unresolved == 0)
    #expect(c.noShow == 1)
    #expect(c.rate == 0)
}

@Test func consistencyRespectsWindowStart() async throws {
    let env = try makeEnv()
    try await addSession(env, daysAgo: 40, weight: 100, status: .cancelled)
    try await addSession(env, daysAgo: 10, weight: 100, status: .completed)

    let all = try await env.reporting.consistency(clientId: env.clientId, from: nil, to: .now)
    #expect(all.rate == 0.5)
    let fourWeeks = try await env.reporting.consistency(
        clientId: env.clientId, from: ReportWindow.fourWeeks.start(from: .now), to: .now)
    #expect(fourWeeks == ConsistencySummary(completed: 1, cancelled: 0, noShow: 0, unresolved: 0))
    #expect(ReportWindow.all.start(from: .now) == nil)
}

@Test func sessionVolumeSumsWeightTimesReps() async throws {
    let env = try makeEnv()
    let squat = try await makeExercise(env, name: "Squat", unit: .lb)
    let id = try await addSession(env, start: daysAgo(3), sets: [(185, 5), (185, 5), (nil, 10), (200, nil)],
                                  status: .completed, exerciseId: squat)

    let volumes = try await env.reporting.sessionVolumes(clientId: env.clientId, from: nil, to: .now)
    #expect(volumes.map(\.id) == [id])
    #expect(volumes[0].totals.byUnit == [.lb: 1850])
}

@Test func volumeKeepsUnitsSeparate() async throws {
    let env = try makeEnv()
    let squat = try await makeExercise(env, name: "Squat", unit: .lb)
    let press = try await makeExercise(env, name: "Press", unit: .kg)
    let start = daysAgo(2)
    let session = try await addSession(env, start: start, sets: [(100, 10)], status: .completed, exerciseId: squat)
    let instance = try await env.sessions.get(id: session)!.instances.first!.id
    try await env.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: instance, exerciseId: press, setIndex: 0, weight: 40, reps: 5,
        duration: nil, distance: nil, rpe: nil, performedAt: start, createdAt: .now, updatedAt: .now))

    let volumes = try await env.reporting.sessionVolumes(clientId: env.clientId, from: nil, to: .now)
    #expect(volumes[0].totals.byUnit == [.lb: 1000, .kg: 200])
    #expect(WeightFormatter.volumeString(volumes[0].totals) == "1,000 lb · 200 kg")
}

@Test func weeklyVolumeGroupsByCalendarWeek() async throws {
    let env = try makeEnv()
    let squat = try await makeExercise(env, name: "Squat", unit: .lb)
    try await addSession(env, start: midWeek(weeksAgo: 2), sets: [(100, 10)], status: .completed, exerciseId: squat)
    try await addSession(env, start: midWeek(weeksAgo: 1), sets: [(100, 10)], status: .completed, exerciseId: squat)
    try await addSession(env, start: midWeek(weeksAgo: 1).addingTimeInterval(86_400), sets: [(100, 5)],
                         status: .completed, exerciseId: squat)
    try await addSession(env, start: midWeek(weeksAgo: 1), sets: [(500, 5)], status: .cancelled, exerciseId: squat)

    let weeks = try await env.reporting.weeklyVolumes(clientId: env.clientId, from: nil, to: .now)
    #expect(weeks.map { $0.totals.byUnit[.lb] } == [1000, 1500])
    #expect(weeks[0].id < weeks[1].id)
}

@Test func topExercisesRankBySessionCountThenRecency() async throws {
    let env = try makeEnv()
    let squat = try await makeExercise(env, name: "Squat", unit: .lb)
    let bench = try await makeExercise(env, name: "Bench", unit: .lb)
    let row = try await makeExercise(env, name: "Row", unit: .lb)
    try await addSession(env, start: daysAgo(20), sets: [(100, 5)], status: .completed, exerciseId: squat)
    try await addSession(env, start: daysAgo(10), sets: [(120, 5)], status: .completed, exerciseId: squat)
    try await addSession(env, start: daysAgo(5), sets: [(80, 5)], status: .completed, exerciseId: bench)
    try await addSession(env, start: daysAgo(2), sets: [(60, 5)], status: .completed, exerciseId: row)
    try await addSession(env, start: daysAgo(1), sets: [(200, 5)], status: .cancelled, exerciseId: bench)

    let top = try await env.reporting.topExercises(clientId: env.clientId)
    #expect(top.map(\.id) == [squat, row, bench])
    #expect(top[0].sessionCount == 2)
    #expect(top[0].bestWeight == 120)
}

@Test func topExercisesReportBestRepsForUnweighted() async throws {
    let env = try makeEnv()
    let pushup = try await makeExercise(env, name: "Push-up", unit: .lb)
    try await addSession(env, start: daysAgo(5), sets: [(nil, 15), (nil, 12)], status: .completed, exerciseId: pushup)
    try await addSession(env, start: daysAgo(2), sets: [(nil, 20), (nil, 10)], status: .completed, exerciseId: pushup)

    let top = try await env.reporting.topExercises(clientId: env.clientId)
    #expect(top.count == 1)
    #expect(top[0].bestWeight == nil)
    #expect(top[0].bestTotalReps == 30)
}
