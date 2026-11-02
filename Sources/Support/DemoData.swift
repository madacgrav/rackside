#if DEBUG
import Foundation
import SwiftData

/// Realistic in-memory sample data for `-demoData` launches (screenshots). Seeds
/// through DTO → model inserts like `PreviewFixtures`; never touches the disk store.
@MainActor
enum DemoData {
    struct Dataset {
        var sessions: [SessionDTO] = []
        var sets: [SetRecordDTO] = []
        /// Jordan's next session (starting shortly after launch), partly recorded — the "session" screen.
        var todaySession: SessionDTO?
    }

    /// Built once per launch so routes and the container agree on ids.
    static let current = dataset(now: .now, calendar: .current)

    static func container(_ dataset: Dataset = current) throws -> ModelContainer {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        exercises.forEach { ctx.insert($0.toModel()) }
        workouts.forEach { ctx.insert($0.toModel()) }
        clients.forEach { ctx.insert($0.toModel()) }
        ctx.insert(screening.toModel())
        assessments.forEach { ctx.insert($0.toModel()) }
        ctx.insert(waiverTemplate.toModel())
        ctx.insert(waiverRecord.toModel())
        dataset.sessions.forEach { ctx.insert($0.toModel()) }
        dataset.sets.forEach { ctx.insert($0.toModel()) }
        try ctx.save()
        return container
    }

    // MARK: Exercises

    private static func exercise(_ name: String, _ category: ExerciseCategory, _ metrics: MetricSet, _ unit: Unit) -> ExerciseDTO {
        ExerciseDTO(id: UUID(), name: name, category: category, metrics: metrics, defaultUnit: unit,
                    isCustom: false, createdAt: .now, updatedAt: .now)
    }

    static let backSquat = exercise("Barbell Back Squat", .strength, [.weight, .reps, .sets], .lb)
    static let bench = exercise("Bench Press", .strength, [.weight, .reps, .sets], .lb)
    static let deadlift = exercise("Deadlift", .strength, [.weight, .reps, .sets], .lb)
    static let overheadPress = exercise("Overhead Press", .strength, [.weight, .reps, .sets], .lb)
    static let row = exercise("Bent-Over Row", .strength, [.weight, .reps, .sets], .lb)
    static let gobletSquat = exercise("Goblet Squat", .strength, [.weight, .reps, .sets], .lb)
    static let romanianDeadlift = exercise("Romanian Deadlift", .strength, [.weight, .reps, .sets], .lb)
    static let pushUp = exercise("Push-up", .bodyweight, [.reps, .sets], .lb)
    static let plank = exercise("Plank", .bodyweight, [.duration], .sec)
    static let lunge = exercise("Walking Lunge", .bodyweight, [.reps, .sets], .lb)
    static let rower = exercise("Rowing Machine", .cardio, [.distance, .duration], .km)
    static let hipFlexor = exercise("Hip Flexor Stretch", .mobility, [.duration], .sec)

    static let exercises = [backSquat, bench, deadlift, overheadPress, row, gobletSquat,
                            romanianDeadlift, pushUp, plank, lunge, rower, hipFlexor]

    // MARK: Workouts

    private static func workout(_ name: String, _ entries: [(ExerciseDTO, sets: Int?, reps: Int?, weight: Double?, seconds: Int?)]) -> WorkoutDTO {
        WorkoutDTO(id: UUID(), name: name, entries: entries.enumerated().map { i, e in
            WorkoutEntryDTO(id: UUID(), exerciseId: e.0.id, order: i, targetSets: e.sets, targetReps: e.reps,
                            targetWeight: e.weight, targetDuration: e.seconds)
        }, createdAt: .now, updatedAt: .now)
    }

    static let lowerStrength = workout("Lower Strength", [
        (backSquat, 5, 5, 205, nil), (romanianDeadlift, 3, 8, 155, nil), (lunge, 3, 10, nil, nil), (plank, 3, nil, nil, 45),
    ])
    static let upperPush = workout("Upper Push", [
        (bench, 4, 6, 145, nil), (overheadPress, 3, 8, 85, nil), (row, 3, 10, 115, nil), (pushUp, 3, 15, nil, nil),
    ])
    static let conditioning = workout("Full Body Conditioning", [
        (gobletSquat, 3, 12, 50, nil), (row, 3, 12, 75, nil), (pushUp, 3, 12, nil, nil), (plank, 3, nil, nil, 45),
    ])
    static let mobility = workout("Mobility Reset", [
        (hipFlexor, 2, nil, nil, 60), (gobletSquat, 2, 10, 25, nil), (plank, 2, nil, nil, 30),
    ])

    static let workouts = [lowerStrength, upperPush, conditioning, mobility]

    // MARK: Clients (fictional 555 numbers)

    private static func years(_ n: Int) -> Date? { Calendar.current.date(byAdding: .year, value: -n, to: .now) }

    static let jordan = ClientDTO(
        id: UUID(), name: "Jordan Lee", phoneE164: "+15555550142",
        goal: "Squat 225 lb by spring", injuries: "Old right shoulder strain — no behind-neck pressing",
        notes: "Prefers early mornings.", isArchived: false, createdAt: .now, updatedAt: .now,
        dateOfBirth: years(31), emergencyName: "Casey Lee", emergencyRelationship: "Partner",
        emergencyPhoneE164: "+15555550188", occupation: "Software engineer (desk-based)",
        trainingHistory: "Recreational lifting for 3 years", availability: "Mon/Thu 7:00"
    )
    static let priya = ClientDTO(
        id: UUID(), name: "Priya Shah", phoneE164: "+15555550113", goal: "Run a sub-25-minute 5K",
        injuries: nil, notes: nil, isArchived: false, createdAt: .now, updatedAt: .now
    )
    static let marcus = ClientDTO(
        id: UUID(), name: "Marcus Bell", phoneE164: "+15555550127", goal: "Rebuild strength after back rehab",
        injuries: "Lower back — keep deadlifts light", notes: nil, isArchived: false, createdAt: .now, updatedAt: .now
    )
    static let elena = ClientDTO(
        id: UUID(), name: "Elena García", phoneE164: "+15555550164", goal: "Stay strong for ski season",
        injuries: nil, notes: nil, isArchived: false, createdAt: .now, updatedAt: .now
    )
    static let tom = ClientDTO(
        id: UUID(), name: "Tom Becker", phoneE164: "+15555550179", goal: "Lose 15 lb and keep it off",
        injuries: nil, notes: nil, isArchived: false, createdAt: .now, updatedAt: .now
    )
    static let me = ClientDTO(
        id: UUID(), name: "Alex Morgan", phoneE164: "", goal: "Keep up my own training",
        injuries: nil, notes: nil, isArchived: false, createdAt: .now, updatedAt: .now, isSelf: true
    )

    static let clients = [jordan, priya, marcus, elena, tom, me]
    static var featuredClient: ClientDTO { jordan }

    // MARK: Intake (featured client)

    static let screening = HealthScreeningDTO(
        id: UUID(), clientId: jordan.id, completedOn: Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now)!,
        answers: [], conditions: nil, surgeries: nil, medications: nil, familyHeartHistory: false,
        symptoms: nil, sleepHours: 7, stressLevel: 2, tobacco: false, alcoholPerWeek: 3,
        activityLevel: .light, clearanceReceivedOn: nil, notes: nil, createdAt: .now, updatedAt: .now
    )

    /// Newest first: forward lean and knee cave improved over six weeks.
    static let assessments: [AssessmentDTO] = [
        AssessmentDTO(
            id: UUID(), clientId: jordan.id, performedOn: Calendar.current.date(byAdding: .day, value: -2, to: .now)!,
            sections: .all,
            measurements: Measurements(restingHR: 62, systolic: 116, diastolic: 74, heightCm: 178, weightKg: 81,
                                       waistCm: 84, hipCm: 99, bodyFatPct: 18, pushUps: 28, plankSeconds: 95),
            ohsAnteriorLeft: [.footTurnsOut], slsRight: [.hipDrop], createdAt: .now, updatedAt: .now
        ),
        AssessmentDTO(
            id: UUID(), clientId: jordan.id, performedOn: Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now)!,
            sections: .all,
            measurements: Measurements(restingHR: 68, systolic: 124, diastolic: 80, heightCm: 178, weightKg: 84,
                                       waistCm: 88, hipCm: 101, bodyFatPct: 21, pushUps: 19, plankSeconds: 60),
            ohsAnteriorRight: [.kneeMovesInward], ohsAnteriorLeft: [.footTurnsOut], ohsLateral: [.excessiveForwardLean],
            slsRight: [.hipDrop, .kneeMovesInward], createdAt: .now, updatedAt: .now
        ),
    ]

    static let waiverTemplate = WaiverTemplateDTO(id: UUID(), version: 1, body: starterWaiver, updatedAt: .now)
    static let waiverRecord = WaiverRecordDTO(
        id: UUID(), clientId: jordan.id, sentOn: Calendar.current.date(byAdding: .day, value: -58, to: .now)!,
        templateVersion: 1, templateBody: starterWaiver,
        returnedSignedOn: Calendar.current.date(byAdding: .day, value: -56, to: .now)!,
        notes: nil, createdAt: .now, updatedAt: .now
    )

    private static var starterWaiver: String {
        Bundle.main.url(forResource: "waiver_starter", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "LIABILITY WAIVER"
    }

    // MARK: Sessions and history

    /// Weekly pattern: (client, workout, weekday 1=Sun…7=Sat, hour, minute, load factor).
    private static let pattern: [(ClientDTO, WorkoutDTO, Int, Int, Int, Double)] = [
        (jordan, lowerStrength, 2, 7, 0, 1.0),
        (priya, conditioning, 3, 18, 0, 0.8),
        (marcus, lowerStrength, 4, 17, 30, 0.6),
        (jordan, upperPush, 5, 7, 0, 1.0),
        (elena, mobility, 6, 12, 0, 1.0),
    ]

    static func dataset(now: Date, calendar: Calendar) -> Dataset {
        var data = Dataset()
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let marcusSeries = (UUID(), AppRecurrence(frequency: .weekly, interval: 1, weekdays: [4], endDate: nil, occurrenceCount: nil))

        func day(weekOffset: Int, weekday: Int) -> Date {
            let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart)!
            let shift = (weekday - calendar.component(.weekday, from: start) + 7) % 7
            return calendar.date(byAdding: .day, value: shift, to: start)!
        }

        func add(_ client: ClientDTO, _ workout: WorkoutDTO, on date: Date, hour: Int, minute: Int,
                 status: SessionStatus, factor: Double, weeksAgo: Int, series: (UUID, AppRecurrence)? = nil) -> SessionDTO {
            add(client, workout, start: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!,
                status: status, factor: factor, weeksAgo: weeksAgo, series: series)
        }
        func add(_ client: ClientDTO, _ workout: WorkoutDTO, start: Date,
                 status: SessionStatus, factor: Double, weeksAgo: Int, series: (UUID, AppRecurrence)? = nil) -> SessionDTO {
            let session = makeSession(client, workout, start: start, status: status, series: series)
            data.sessions.append(session)
            if status == .completed {
                data.sets += recordedSets(session, factor: factor, weeksAgo: weeksAgo)
            }
            return session
        }

        // Eight past weeks, all completed except one no-show and one cancellation.
        for weeksAgo in 1...8 {
            for (client, workout, weekday, hour, minute, factor) in pattern {
                if client.id == elena.id && weeksAgo.isMultiple(of: 2) { continue }
                var status = SessionStatus.completed
                if client.id == marcus.id && weeksAgo == 5 { status = .noShow }
                if client.id == priya.id && weeksAgo == 3 { status = .cancelled }
                _ = add(client, workout, on: day(weekOffset: -weeksAgo, weekday: weekday), hour: hour, minute: minute,
                        status: status, factor: factor, weeksAgo: weeksAgo)
            }
        }

        // This week: earlier days completed, later days scheduled; today gets its own three sessions.
        for (client, workout, weekday, hour, minute, factor) in pattern {
            let date = day(weekOffset: 0, weekday: weekday)
            if calendar.isDate(date, inSameDayAs: today) { continue }
            let isMarcus = client.id == marcus.id
            _ = add(client, workout, on: date, hour: hour, minute: minute, status: date < today ? .completed : .scheduled,
                    factor: factor, weeksAgo: 0, series: isMarcus ? marcusSeries : nil)
        }
        // Today's scheduled sessions start after `now`, otherwise reports flag them as
        // "past session still marked scheduled" whenever the screenshots are taken.
        let quarter = 15.0 * 60
        let next = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter + quarter)
        _ = add(priya, conditioning, start: next.addingTimeInterval(-2 * 3600), status: .completed, factor: 0.8, weeksAgo: 0)
        var jordanToday = add(jordan, lowerStrength, start: next, status: .scheduled, factor: 1, weeksAgo: 0)
        jordanToday.notes = "Last week's squats moved well — try 205 for 5×5."
        data.sessions[data.sessions.count - 1] = jordanToday
        let instance = jordanToday.instances[0]
        data.sets += (0..<2).map { i in
            SetRecordDTO(id: UUID(), workoutInstanceId: instance.id, exerciseId: backSquat.id, setIndex: i,
                         weight: 205, reps: 5, duration: nil, distance: nil, rpe: nil,
                         performedAt: now, createdAt: now, updatedAt: now)
        }
        data.todaySession = jordanToday
        _ = add(marcus, lowerStrength, start: next.addingTimeInterval(3 * 3600), status: .scheduled, factor: 0.6,
                weeksAgo: 0, series: marcusSeries)
        return data
    }

    private static func makeSession(_ client: ClientDTO, _ workout: WorkoutDTO, start: Date,
                                    status: SessionStatus, series: (UUID, AppRecurrence)?) -> SessionDTO {
        // Instance and entry ids are unique in the store, so every session gets fresh ones.
        let instance = WorkoutInstanceDTO(
            id: UUID(), sourceWorkoutId: workout.id, name: workout.name,
            plannedEntries: workout.entries.map {
                PlannedEntryDTO(id: UUID(), exerciseId: $0.exerciseId, order: $0.order, targetSets: $0.targetSets,
                                targetReps: $0.targetReps, targetWeight: $0.targetWeight, targetDuration: $0.targetDuration)
            }
        )
        return SessionDTO(
            id: UUID(), clientId: client.id, startAt: start, endAt: start.addingTimeInterval(3600),
            status: status, notes: nil, instances: [instance],
            seriesId: series?.0, recurrence: series?.1, eventIdentifier: nil, createdAt: start, updatedAt: start
        )
    }

    /// Every planned set, with loads that climb ~7 lb a week on the main lifts so charts rise.
    private static func recordedSets(_ session: SessionDTO, factor: Double, weeksAgo: Int) -> [SetRecordDTO] {
        session.instances.flatMap { instance in
            instance.plannedEntries.flatMap { entry -> [SetRecordDTO] in
                let step: Double = entry.exerciseId == backSquat.id ? 7 : entry.exerciseId == bench.id ? 4 : 2.5
                let weight = entry.targetWeight.map { max(20, (($0 - step * Double(weeksAgo)) * factor / 5).rounded() * 5) }
                return (0..<(entry.targetSets ?? 1)).map { i in
                    let at = session.startAt.addingTimeInterval(Double(entry.order * 600 + i * 120))
                    return SetRecordDTO(
                        id: UUID(), workoutInstanceId: instance.id, exerciseId: entry.exerciseId, setIndex: i,
                        weight: weight, reps: entry.targetReps.map { i == 2 && weeksAgo > 4 ? $0 - 1 : $0 },
                        duration: entry.targetDuration, distance: nil, rpe: nil,
                        performedAt: at, createdAt: at, updatedAt: at
                    )
                }
            }
        }
    }
}
#endif
