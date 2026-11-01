import SwiftUI

struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    private let sessionRepo: any SessionRepository
    /// Receives a calendar warning (nil when the calendar step succeeded or
    /// was not requested). The session itself is always saved by then.
    private let onSaved: (String?) -> Void

    @State private var clients: [ClientDTO] = []
    @State private var workouts: [WorkoutDTO] = []
    @State private var selectedClientId: UUID?
    @State private var startAt: Date
    @State private var durationMinutes = 60
    @State private var selectedWorkoutIds: Set<UUID> = []
    @State private var notes = ""

    @State private var repeats = false
    @State private var repeatWeekdays: Set<Int> = []
    @State private var repeatWeeks = 8
    @State private var addToCalendar = false
    @State private var errorMessage: String?
    @State private var calendarWarning: String?

    private let clientRepo: any ClientRepository
    /// Optional because editing never re-attaches workouts (instances are frozen).
    private let workoutRepo: (any WorkoutRepository)?
    private let calendar: any CalendarSyncing
    private let existing: SessionDTO?
    /// For a series occurrence: `.following` edits this and later sessions;
    /// anything else edits this session alone (it leaves the series).
    private let scope: SeriesScope?

    init(
        sessionRepo: any SessionRepository,
        clientRepo: any ClientRepository,
        workoutRepo: (any WorkoutRepository)? = nil,
        calendar: any CalendarSyncing = EventKitCalendarService(),
        existing: SessionDTO? = nil,
        scope: SeriesScope? = nil,
        initialDate: Date,
        onSaved: @escaping (String?) -> Void
    ) {
        self.sessionRepo = sessionRepo
        self.clientRepo = clientRepo
        self.workoutRepo = workoutRepo
        self.calendar = calendar
        self.existing = existing
        self.scope = scope
        self.onSaved = onSaved
        if let existing {
            _selectedClientId = State(initialValue: existing.clientId)
            _startAt = State(initialValue: existing.startAt)
            _durationMinutes = State(initialValue: max(15, Int(existing.endAt.timeIntervalSince(existing.startAt) / 60)))
            _notes = State(initialValue: existing.notes ?? "")
            _addToCalendar = State(initialValue: existing.eventIdentifier != nil)
        } else {
            let calendar = Calendar.current
            let base = calendar.startOfDay(for: initialDate)
            _startAt = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? initialDate)
        }
    }

    private var isEditing: Bool { existing != nil }

    private var editsFollowing: Bool { scope == .following && existing?.seriesId != nil }

    private var canSave: Bool { selectedClientId != nil }

    private static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            Form {
                if !editsFollowing {
                Section("Client") {
                    Picker("Client", selection: $selectedClientId) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(clients) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                    }
                }
                }
                Section {
                    if editsFollowing {
                        DatePicker("Starts", selection: $startAt, displayedComponents: .hourAndMinute)
                    } else {
                        DatePicker("Starts", selection: $startAt)
                    }
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                } header: {
                    Text("When")
                } footer: {
                    if editsFollowing {
                        Text("Changes this session and the scheduled sessions after it.")
                    }
                }
                if !isEditing {
                Section("Workouts") {
                    if workouts.isEmpty {
                        Text("No workout templates yet").foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { workout in
                        Button {
                            if selectedWorkoutIds.contains(workout.id) {
                                selectedWorkoutIds.remove(workout.id)
                            } else {
                                selectedWorkoutIds.insert(workout.id)
                            }
                        } label: {
                            HStack {
                                Text(workout.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedWorkoutIds.contains(workout.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("Repeat") {
                    Toggle("Repeats weekly", isOn: $repeats)
                    if repeats {
                        HStack {
                            ForEach(1...7, id: \.self) { weekday in
                                let symbol = Self.weekdaySymbols[weekday - 1]
                                Button(symbol) {
                                    if repeatWeekdays.contains(weekday) {
                                        repeatWeekdays.remove(weekday)
                                    } else {
                                        repeatWeekdays.insert(weekday)
                                    }
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .tint(repeatWeekdays.contains(weekday) ? Theme.Colors.accent : Color.secondary)
                            }
                        }
                        Stepper("For \(repeatWeeks) weeks", value: $repeatWeeks, in: 1...26)
                    }
                }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                ErrorBanner(message: errorMessage)
                if !editsFollowing {
                Section {
                    Toggle(isEditing ? "Keep in iPhone calendar" : "Add to iPhone calendar", isOn: $addToCalendar)
                } footer: {
                    Text("Pushes the session to your default calendar (syncs to Google Calendar if that's your default account).")
                }
                }
            }
            .navigationTitle(editsFollowing ? "Edit Following Sessions" : isEditing ? "Edit Session" : "New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await save() {
                                onSaved(calendarWarning)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
            .task {
                clients = (try? await clientRepo.all()) ?? []
                // A solo user training themselves should not have to pick every time.
                if selectedClientId == nil, clients.count == 1 { selectedClientId = clients[0].id }
                if let workoutRepo {
                    workouts = (try? await workoutRepo.all()) ?? []
                }
            }
        }
    }

    private func save() async -> Bool {
        guard let clientId = selectedClientId else { return false }
        errorMessage = nil
        calendarWarning = nil
        if let existing, editsFollowing {
            let time = Calendar.current.dateComponents([.hour, .minute], from: startAt)
            let clientName = clients.first { $0.id == existing.clientId }?.name ?? "Client"
            do {
                let result = try await SeriesActions(sessionRepo: sessionRepo, calendar: calendar).editFollowing(
                    from: existing, hour: time.hour ?? 9, minute: time.minute ?? 0,
                    duration: TimeInterval(durationMinutes * 60),
                    notes: notes.isEmpty ? nil : notes, clientName: clientName
                )
                calendarWarning = result.outcome.calendarWarning
                return true
            } catch {
                errorMessage = "Couldn't save the sessions. Please try again."
                return false
            }
        }
        if let existing {
            var base = existing
            if existing.seriesId != nil {
                // A series row is never edited in place: it leaves the series
                // first, with its own calendar event, then the normal edit runs.
                let clientName = clients.first { $0.id == existing.clientId }?.name ?? "Client"
                do {
                    let (detached, outcome) = try await SeriesActions(sessionRepo: sessionRepo, calendar: calendar)
                        .detach(existing, clientName: clientName)
                    base = detached
                    calendarWarning = outcome.calendarWarning
                } catch {
                    errorMessage = "Couldn't save the session. Please try again."
                    return false
                }
            }
            return await saveEdit(of: base, clientId: clientId)
        }
        let dto = SessionDTO(
            id: UUID(),
            clientId: clientId,
            startAt: startAt,
            endAt: startAt.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            status: .scheduled,
            notes: notes.isEmpty ? nil : notes,
            instances: [],
            seriesId: nil,
            recurrence: nil,
            eventIdentifier: nil,
            createdAt: .now,
            updatedAt: .now
        )
        let workoutIds = Array(selectedWorkoutIds)
        let clientName = clients.first { $0.id == clientId }?.name ?? "Client"
        if repeats {
            let rule = AppRecurrence(
                frequency: .weekly,
                interval: 1,
                weekdays: repeatWeekdays.sorted(),
                endDate: nil,
                occurrenceCount: nil
            )
            let series: ScheduledSeries
            do {
                series = try await sessionRepo.scheduleSeries(dto, recurrence: rule, attaching: workoutIds, horizonWeeks: repeatWeeks)
            } catch {
                errorMessage = "Couldn't schedule the session. Please try again."
                return false
            }
            if addToCalendar, let firstStart = series.occurrences.first {
                let hasAccess = await calendar.requestAccess()
                var result: Result<String?, any Error>?
                if hasAccess {
                    // Anchor the calendar event on the first real occurrence and cap
                    // it at the number of sessions actually created. EventKit always
                    // keeps the event's own start date even when its weekday is not
                    // in the rule, so anchoring on `dto.startAt` (e.g. a Wednesday
                    // for a Tue/Thu series) would add a phantom calendar entry.
                    var anchor = dto
                    anchor.startAt = firstStart
                    anchor.endAt = firstStart.addingTimeInterval(dto.endAt.timeIntervalSince(dto.startAt))
                    var boundedRule = rule
                    boundedRule.occurrenceCount = series.occurrences.count
                    result = await capturing {
                        try await calendar.push(anchor, clientName: clientName, recurrence: boundedRule)
                    }
                }
                await apply(
                    resolveEventIdentifier(existing: nil, wantsCalendar: true, hasAccess: hasAccess, result: result),
                    store: { try await sessionRepo.setEventIdentifierForSeries(series.seriesId, $0) }
                )
            }
        } else {
            do {
                try await sessionRepo.schedule(dto, attaching: workoutIds)
            } catch {
                errorMessage = "Couldn't schedule the session. Please try again."
                return false
            }
            // Calendar failures never block saving; the session is already stored.
            if addToCalendar {
                let hasAccess = await calendar.requestAccess()
                let result: Result<String?, any Error>? = hasAccess
                    ? await capturing { try await calendar.push(dto, clientName: clientName, recurrence: nil) }
                    : nil
                await apply(
                    resolveEventIdentifier(existing: nil, wantsCalendar: true, hasAccess: hasAccess, result: result),
                    store: { try await sessionRepo.setEventIdentifier(id: dto.id, $0) }
                )
            }
        }
        return true
    }

    /// Edit path: time window, client and notes change; instances stay frozen.
    private func saveEdit(of existing: SessionDTO, clientId: UUID) async -> Bool {
        var updated = existing
        updated.clientId = clientId
        updated.startAt = startAt
        updated.endAt = startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        updated.notes = notes.isEmpty ? nil : notes
        do {
            try await sessionRepo.update(updated)
        } catch {
            errorMessage = "Couldn't save the session. Please try again."
            return false
        }
        let clientName = clients.first { $0.id == clientId }?.name ?? "Client"
        let hasAccess = addToCalendar ? await calendar.requestAccess() : false
        let result: Result<String?, any Error>?
        if addToCalendar, hasAccess {
            result = await capturing {
                if let eventId = existing.eventIdentifier {
                    try await calendar.update(eventIdentifier: eventId, updated, clientName: clientName)
                } else {
                    try await calendar.push(updated, clientName: clientName, recurrence: nil)
                }
            }
        } else if !addToCalendar, let eventId = existing.eventIdentifier {
            result = await capturing { () async throws -> String? in
                try await calendar.remove(eventIdentifier: eventId)
                return nil
            }
        } else {
            result = nil
        }
        await apply(
            resolveEventIdentifier(
                existing: existing.eventIdentifier, wantsCalendar: addToCalendar,
                hasAccess: hasAccess, result: result
            ),
            store: { try await sessionRepo.setEventIdentifier(id: updated.id, $0) }
        )
        return true
    }

    /// Persists a resolved calendar outcome. Store failures become a warning,
    /// never a blocked save: the session row already exists.
    private func apply(_ outcome: CalendarOutcome, store: (String?) async throws -> Void) async {
        switch outcome {
        case .unchanged:
            break
        case .store(let identifier):
            do {
                try await store(identifier)
            } catch {
                Log.calendar.error("setEventIdentifier failed: \(error.localizedDescription)")
                calendarWarning = "Saved, but the calendar link couldn't be recorded."
            }
        case .failed(let message):
            Log.calendar.error("Calendar step failed: \(message)")
            calendarWarning = message
        }
    }
}

#Preview("New session") {
    let repos = PreviewFixtures.repositories()
    SessionEditView(
        sessionRepo: repos.sessions,
        clientRepo: repos.clients,
        workoutRepo: repos.workouts,
        initialDate: .now
    ) { _ in }
}
