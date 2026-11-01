import SwiftUI

struct SessionRunView: View {
    @State var viewModel: SessionRunViewModel
    /// Only needed by the edit sheet's "new session" mode; presenters without a
    /// workout repository (client detail) pass nothing.
    var workoutRepo: (any WorkoutRepository)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingTextReminder = false
    @State private var pendingStatus: SessionStatus?
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var calendarWarning: String?
    /// A delete succeeded with a calendar warning: dismiss once it is read.
    @State private var dismissAfterWarning = false
    /// Series occurrence awaiting a "this only / following" choice.
    @State private var scopePrompt: ScopePrompt?

    /// Scope chosen for the edit sheet of a series occurrence.
    @State private var editScope: SeriesScope?

    private enum ScopePrompt: Identifiable {
        case edit, cancel, delete
        var id: Self { self }

        var title: String {
            switch self {
            case .edit: "Edit repeating session"
            case .cancel: "Cancel repeating session"
            case .delete: "Delete repeating session"
            }
        }

        var message: String {
            switch self {
            case .edit: "Changing following sessions moves them to a new series at the new time."
            case .cancel: "Completed sessions and sessions with logged sets aren't changed."
            case .delete: "Logged sets are deleted with a session. Later sessions that already have logged sets are kept and leave the series."
            }
        }
    }
    @State private var pendingDeleteSet: SetRecordDTO?

    private var hasInjuries: Bool { !(viewModel.clientInjuries ?? "").isEmpty }

    var body: some View {
        List {
            ErrorBanner(message: viewModel.errorMessage)
            if hasInjuries || viewModel.clearanceNeeded {
                Section {
                    if viewModel.clearanceNeeded {
                        Label("Medical clearance recommended", systemImage: "cross.case.fill")
                            .foregroundStyle(Theme.Colors.warning)
                            .font(.callout)
                    }
                    if let injuries = viewModel.clientInjuries, hasInjuries {
                        Label(injuries, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.warning)
                            .font(.callout)
                    }
                } header: {
                    Text("Health & limitations")
                }
            }

            Section {
                LabeledContent("Time", value: viewModel.session.startAt.formatted(date: .abbreviated, time: .shortened))
                if viewModel.isSeries {
                    Label("Repeats weekly", systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: statusLabel)
            }

            Section("Notes") {
                TextField("Session notes", text: $viewModel.notesDraft, axis: .vertical)
                    .lineLimit(2...6)
                    .onSubmit { Task { await viewModel.saveNotes() } }
                if viewModel.notesDraft != (viewModel.session.notes ?? "") {
                    Button("Save notes") { Task { await viewModel.saveNotes() } }
                }
            }

            ForEach(viewModel.session.instances) { instance in
                Section(instance.name) {
                    ForEach(instance.plannedEntries) { entry in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            TitleCaptionRow(
                                title: viewModel.exercises[entry.exerciseId]?.name ?? "Exercise",
                                caption: targetText(entry)
                            )
                            SetTableView(
                                entry: entry,
                                exercise: viewModel.exercises[entry.exerciseId],
                                logged: viewModel.sets(instanceId: instance.id, exerciseId: entry.exerciseId),
                                previous: viewModel.previousSets[entry.exerciseId],
                                onLog: { draft in
                                    Task { await viewModel.record(draft: draft, instanceId: instance.id, exerciseId: entry.exerciseId) }
                                },
                                onDelete: { pendingDeleteSet = $0 }
                            )
                        }
                        .themedRows()
                    }
                }
            }

            if viewModel.session.status == .scheduled {
                Section {
                    Button("Mark Completed", systemImage: "checkmark.circle") {
                        pendingStatus = .completed
                    }
                    Button("Cancelled", systemImage: "xmark.circle", role: .destructive) {
                        if viewModel.isSeries { scopePrompt = .cancel } else { pendingStatus = .cancelled }
                    }
                    Button("No-show", systemImage: "person.fill.xmark", role: .destructive) {
                        pendingStatus = .noShow
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(viewModel.clientName)
        .safeAreaInset(edge: .top) {
            if viewModel.session.status == .scheduled, viewModel.plannedSetCount > 0 {
                ProgressView(value: viewModel.progress)
                    .tint(Theme.Colors.success)
                    .padding(.horizontal)
                    .accessibilityLabel("Session progress")
                    .accessibilityValue("\(viewModel.loggedSetCount) of \(viewModel.plannedSetCount) sets")
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.lastLoggedSetId)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let phone = viewModel.clientPhone, !phone.isEmpty, MessagingService.canSendText {
                    Button("Text reminder", systemImage: "message") {
                        showingTextReminder = true
                    }
                }
                Menu {
                    Button("Edit session", systemImage: "pencil") {
                        if viewModel.isSeries { scopePrompt = .edit } else { showingEdit = true }
                    }
                    Button("Delete session", systemImage: "trash", role: .destructive) {
                        if viewModel.isSeries { scopePrompt = .delete } else { confirmingDelete = true }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }
                .accessibilityLabel("More actions")
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: { editScope = nil }) {
            SessionEditView(
                sessionRepo: viewModel.sessionRepo,
                clientRepo: viewModel.clientRepo,
                workoutRepo: workoutRepo,
                existing: viewModel.session,
                scope: editScope,
                initialDate: viewModel.session.startAt
            ) { warning in
                calendarWarning = warning
                Task { await viewModel.reloadAfterEdit() }
            }
        }
        .alert(
            "Calendar",
            isPresented: Binding(
                get: { (calendarWarning ?? viewModel.calendarWarning) != nil },
                set: { if !$0 { clearCalendarWarning() } }
            )
        ) {
            Button("OK") { clearCalendarWarning() }
        } message: {
            Text(calendarWarning ?? viewModel.calendarWarning ?? "")
        }
        .alert("Delete this session?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    guard await viewModel.delete() else { return }
                    if viewModel.calendarWarning == nil { dismiss() } else { dismissAfterWarning = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(!viewModel.isSeries
                 ? "Logged sets for this session are deleted too. This cannot be undone."
                 : "Only this occurrence is deleted and removed from your calendar; the rest of the series stays.")
        }
        .sheet(isPresented: $showingTextReminder) {
            if let phone = viewModel.clientPhone {
                MessageComposeView(
                    recipient: phone,
                    body: MessagingService.reminderBody(
                        clientName: viewModel.clientName,
                        sessionDate: viewModel.session.startAt
                    )
                )
                .ignoresSafeArea()
            }
        }
        .alert(
            statusAlertTitle,
            isPresented: Binding(get: { pendingStatus != nil }, set: { if !$0 { pendingStatus = nil } })
        ) {
            Button(statusAlertConfirm, role: pendingStatus == .completed ? nil : .destructive) {
                if let status = pendingStatus { Task { await viewModel.setStatus(status) } }
                pendingStatus = nil
            }
            Button("Keep", role: .cancel) { pendingStatus = nil }
        } message: {
            Text(pendingStatus == .completed
                 ? "You can still log or delete sets afterwards."
                 : "This can't be changed back from the app.")
        }
        .confirmationDialog(
            scopePrompt?.title ?? "",
            isPresented: Binding(get: { scopePrompt != nil }, set: { if !$0 { scopePrompt = nil } }),
            titleVisibility: .visible,
            presenting: scopePrompt
        ) { prompt in
            let role: ButtonRole? = prompt == .edit ? nil : .destructive
            Button("This session only", role: role) { run(prompt, scope: .thisOnly) }
            Button("This and following sessions", role: role) { run(prompt, scope: .following) }
            Button(prompt == .edit ? "Cancel" : "Keep", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .confirmationDialog(
            "Delete this set?",
            isPresented: Binding(get: { pendingDeleteSet != nil }, set: { if !$0 { pendingDeleteSet = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete set", role: .destructive) {
                if let set = pendingDeleteSet { Task { await viewModel.deleteSet(set) } }
                pendingDeleteSet = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSet = nil }
        }
        .task { await viewModel.load() }
    }

    private func run(_ prompt: ScopePrompt, scope: SeriesScope) {
        if prompt == .edit {
            editScope = scope
            showingEdit = true
            return
        }
        Task {
            switch prompt {
            case .edit:
                break
            case .cancel:
                await viewModel.setStatus(.cancelled, scope: scope)
            case .delete:
                guard await viewModel.delete(scope: scope) else { return }
                if viewModel.calendarWarning == nil { dismiss() } else { dismissAfterWarning = true }
            }
        }
    }

    private func clearCalendarWarning() {
        calendarWarning = nil
        viewModel.calendarWarning = nil
        if dismissAfterWarning {
            dismissAfterWarning = false
            dismiss()
        }
    }

    private var statusAlertTitle: String {
        switch pendingStatus {
        case .completed: "Mark completed?"
        case .noShow: "Mark as no-show?"
        default: "Cancel this session?"
        }
    }

    private var statusAlertConfirm: String {
        switch pendingStatus {
        case .completed: "Mark completed"
        case .noShow: "Mark no-show"
        default: "Cancel session"
        }
    }

    private func targetText(_ entry: PlannedEntryDTO) -> String? {
        let exercise = viewModel.exercises[entry.exerciseId]
        var parts: [String] = []
        if let sets = entry.targetSets, let reps = entry.targetReps { parts.append("\(sets)×\(reps)") }
        if let weight = entry.targetWeight {
            parts.append("@ \(WeightFormatter.string(weight, unit: exercise?.defaultUnit ?? .lb))")
        }
        if let duration = entry.targetDuration { parts.append("\(duration)s") }
        return parts.isEmpty ? nil : "Target: " + parts.joined(separator: " ")
    }

    private var statusLabel: String {
        switch viewModel.session.status {
        case .scheduled: "Scheduled"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .noShow: "No-show"
        }
    }
}

#Preview("Session") {
    let repos = PreviewFixtures.repositories()
    NavigationStack {
        SessionRunView(viewModel: SessionRunViewModel(
            sessionRepo: repos.sessions,
            exerciseRepo: repos.exercises,
            clientRepo: repos.clients,
            session: PreviewFixtures.scheduledSession,
            clientName: "Sam Rivera",
            clientPhone: "+15551234567",
            clientInjuries: "Left knee — avoid deep squats"
        ), workoutRepo: repos.workouts)
    }
}
