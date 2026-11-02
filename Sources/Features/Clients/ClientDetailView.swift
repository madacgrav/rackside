import SwiftUI

struct ClientDetailView: View {
    @State var viewModel: ClientDetailViewModel
    @State private var showingEdit = false
    @State private var confirmingArchive = false

    var body: some View {
        List {
            ErrorBanner(message: viewModel.errorMessage)
                .themedRows()
            Section("Contact") {
                if !viewModel.client.isSelf {
                    LabeledContent("Phone", value: viewModel.client.phoneE164)
                }
                if let goal = viewModel.client.goal {
                    LabeledContent("Goal", value: goal)
                }
                if let injuries = viewModel.client.injuries {
                    LabeledContent("Injuries", value: injuries)
                }
                if let notes = viewModel.client.notes {
                    LabeledContent("Notes", value: notes)
                }
            }
            .themedRows()
            Section("Upcoming Sessions") {
                if viewModel.upcomingSessions.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(.secondary)
                }
                ForEach(viewModel.upcomingSessions) { session in
                    sessionLink(session)
                }
            }
            .themedRows()
            Section("Recent Sessions") {
                if viewModel.recentSessions.isEmpty {
                    Text("No sessions yet").foregroundStyle(.secondary)
                }
                ForEach(viewModel.recentSessions) { session in
                    sessionLink(session)
                }
            }
            .themedRows()
            Section("Progress Reports") {
                NavigationLink("View progress") {
                    ClientReportView(viewModel: ClientReportViewModel(
                        reporting: viewModel.reporting,
                        exerciseRepo: viewModel.exerciseRepo,
                        client: viewModel.client
                    ))
                }
            }
            .themedRows()
            if viewModel.client.isArchived {
                Section {
                    Label("This client is archived", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
                .themedRows()
            }
        }
        .themedScreen()
        .navigationTitle(viewModel.client.isSelf ? "\(viewModel.client.name) (You)" : viewModel.client.name)
        .toolbar {
            Menu {
                Button("Edit") { showingEdit = true }
                Button(
                    viewModel.client.isArchived ? "Unarchive" : "Archive",
                    systemImage: "archivebox"
                ) {
                    confirmingArchive = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .accessibilityLabel("More actions")
        }
        .confirmationDialog(
            viewModel.client.isArchived ? "Unarchive \(viewModel.client.name)?" : "Archive \(viewModel.client.name)?",
            isPresented: $confirmingArchive,
            titleVisibility: .visible
        ) {
            Button(
                viewModel.client.isArchived ? "Unarchive" : "Archive",
                role: viewModel.client.isArchived ? nil : .destructive
            ) {
                Task { await viewModel.toggleArchived() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.client.isArchived
                 ? "The client returns to the roster and the client picker."
                 : "Archived clients leave the roster and the client picker. Their history is kept.")
        }
        .sheet(isPresented: $showingEdit) {
            ClientEditView(repo: viewModel.repository, existing: viewModel.client) {
                Task { await viewModel.reload() }
            }
        }
        .task { await viewModel.reload() }
    }

    private func sessionLink(_ session: SessionDTO) -> some View {
        NavigationLink {
            SessionRunView(viewModel: SessionRunViewModel(
                sessionRepo: viewModel.sessionRepo,
                exerciseRepo: viewModel.exerciseRepo,
                clientRepo: viewModel.repository,
                session: session,
                clientName: viewModel.client.name,
                clientPhone: viewModel.client.phoneE164,
                clientInjuries: viewModel.client.injuries,
                onStatusChanged: { await viewModel.reload() }
            ))
        } label: {
            SessionRow(session: session, clientName: session.startAt.formatted(date: .abbreviated, time: .omitted))
        }
    }
}

#Preview("Client detail") {
    let repos = PreviewFixtures.repositories()
    NavigationStack {
        ClientDetailView(viewModel: ClientDetailViewModel(
            repo: repos.clients,
            exerciseRepo: repos.exercises,
            sessionRepo: repos.sessions,
            reporting: repos.reporting,
            reminders: repos.reminders,
            client: PreviewFixtures.client
        ))
    }
    .environment(TimerStore.preview)
}
