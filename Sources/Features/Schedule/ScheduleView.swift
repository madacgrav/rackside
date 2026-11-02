import SwiftData
import SwiftUI

struct ScheduleView: View {
    @State var viewModel: ScheduleViewModel
    /// Switches the root tab to Settings (used by the export reminder banner).
    var openSettings: () -> Void = {}
    @State private var showingNew = false
    @State private var calendarWarning: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isExportReminderDue {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(Theme.Colors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Back up your data").font(.subheadline.bold())
                            Text("Export is the only backup on this phone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Export") { openSettings() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Dismiss", systemImage: "xmark") { viewModel.dismissExportReminder() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.warning.opacity(0.12))
                }

                Picker("View", selection: $viewModel.mode) {
                    ForEach(ScheduleMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, Theme.Spacing.sm)

                switch viewModel.mode {
                case .day:
                    DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)

                    List(viewModel.sessionsForDay) { session in
                        sessionLink(session)
                    }
                    .overlay {
                        if viewModel.isLoading && viewModel.sessionsForDay.isEmpty {
                            ProgressView()
                        } else if viewModel.sessionsForDay.isEmpty {
                            EmptyState(title: "No sessions this day", systemImage: "calendar")
                        }
                    }
                    .themedScreen()
                case .week:
                    weekHeader
                    weekList
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
            .sheet(isPresented: $showingNew) {
                SessionEditView(
                    sessionRepo: viewModel.sessionRepo,
                    clientRepo: viewModel.clientRepo,
                    workoutRepo: viewModel.workoutRepo,
                    initialDate: viewModel.selectedDate
                ) { warning in
                    calendarWarning = warning
                    Task { await viewModel.load() }
                }
            }
            .alert(
                "Calendar",
                isPresented: Binding(get: { calendarWarning != nil }, set: { if !$0 { calendarWarning = nil } })
            ) {
                Button("OK") { calendarWarning = nil }
            } message: {
                Text(calendarWarning ?? "")
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.selectedDate) {
                Task { await viewModel.load() }
            }
            .onChange(of: viewModel.mode) { Task { await viewModel.load() } }
        }
    }

    private func sessionLink(_ session: SessionDTO) -> some View {
        NavigationLink {
            SessionRunView(viewModel: SessionRunViewModel(
                sessionRepo: viewModel.sessionRepo,
                exerciseRepo: viewModel.exerciseRepo,
                clientRepo: viewModel.clientRepo,
                session: session,
                clientName: viewModel.clientNames[session.clientId] ?? "Client",
                clientPhone: viewModel.clientPhones[session.clientId],
                clientInjuries: viewModel.clientInjuries[session.clientId] ?? nil,
                healthRepo: viewModel.healthRepo,
                onStatusChanged: { await viewModel.load() }
            ), workoutRepo: viewModel.workoutRepo)
        } label: {
            SessionRow(session: session, clientName: viewModel.clientNames[session.clientId] ?? "Client")
        }
        .themedRows()
    }

    private var weekHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconButton(title: "Previous week", systemImage: "chevron.left") { viewModel.showPreviousWeek() }
            Text(viewModel.weekTitle)
                .font(Theme.Fonts.display())
                .frame(maxWidth: .infinity)
            IconButton(title: "Next week", systemImage: "chevron.right") { viewModel.showNextWeek() }
            Button("Today") { viewModel.showToday() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isShowingWeek())
        }
        .padding(.horizontal)
    }

    private var weekList: some View {
        List {
            ForEach(viewModel.week) { day in
                Section(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) {
                    if day.sessions.isEmpty {
                        Text("No sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .themedRows()
                    } else {
                        ForEach(day.sessions) { sessionLink($0) }
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.week.isEmpty { ProgressView() }
        }
        .themedScreen()
    }
}

struct SessionRow: View {
    let session: SessionDTO
    let clientName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(clientName)
                    .font(Theme.Fonts.display())
                Text(session.startAt.formatted(date: .omitted, time: .shortened) + " – "
                     + session.endAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.instances.isEmpty {
                    Text(session.instances.map(\.name).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if session.seriesId != nil {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Repeating")
            }
            StatusChip(status: session.status)
        }
    }
}

#Preview("Schedule") {
    let repos = PreviewFixtures.repositories()
    ScheduleView(viewModel: ScheduleViewModel(
        sessionRepo: repos.sessions,
        clientRepo: repos.clients,
        workoutRepo: repos.workouts,
        exerciseRepo: repos.exercises,
        reminders: repos.reminders
    ))
    .environment(TimerStore.preview)
}

#Preview("Schedule — Week") {
    let repos = PreviewFixtures.repositories(seedingWeek: true)
    let viewModel = ScheduleViewModel(
        sessionRepo: repos.sessions,
        clientRepo: repos.clients,
        workoutRepo: repos.workouts,
        exerciseRepo: repos.exercises,
        reminders: repos.reminders,
        defaults: UserDefaults(suiteName: "ScheduleWeekPreview")!
    )
    viewModel.mode = .week
    return ScheduleView(viewModel: viewModel)
        .environment(TimerStore.preview)
}

#Preview("Session row") {
    List {
        SessionRow(session: PreviewFixtures.scheduledSession, clientName: "Sam Rivera")
        SessionRow(session: { var s = PreviewFixtures.scheduledSession; s.status = .completed; return s }(), clientName: "Sam Rivera")
        SessionRow(session: { var s = PreviewFixtures.scheduledSession; s.status = .noShow; return s }(), clientName: "Sam Rivera")
        SessionRow(session: PreviewFixtures.seriesSession, clientName: "Sam Rivera")
    }
}
