import SwiftUI

struct ClientListView: View {
    @State var viewModel: ClientListViewModel
    @State private var showingAdd = false
    @State private var showingSelf = false
    /// Set by the first-run notice in RootView; consumed once to open the self sheet.
    @AppStorage("wantsSelfClient") private var wantsSelfClient = false
    @AppStorage("defaultWeightUnit") private var defaultWeightUnit: String = Unit.lb.rawValue
    /// A client just created from the Add sheet, offered intake once the sheet closes.
    @State private var pendingIntake: ClientDTO?
    @State private var showingIntakeOffer = false
    @State private var intakeClient: ClientDTO?

    var body: some View {
        NavigationStack {
            List(viewModel.clients) { client in
                NavigationLink {
                    ClientDetailView(viewModel: ClientDetailViewModel(
                        repo: viewModel.repository,
                        exerciseRepo: viewModel.exerciseRepo,
                        sessionRepo: viewModel.sessionRepo,
                        reporting: viewModel.reporting,
                        reminders: viewModel.reminders,
                        intake: viewModel.intake,
                        client: client
                    ))
                } label: {
                    TitleCaptionRow(title: client.name, caption: client.goal)
                }
                .themedRows()
            }
            .overlay {
                if viewModel.isLoading && viewModel.clients.isEmpty {
                    ProgressView()
                } else if viewModel.clients.isEmpty {
                    EmptyState(
                        title: viewModel.query.isEmpty ? "No clients yet" : "No matches",
                        systemImage: "person.2.fill",
                        action: viewModel.query.isEmpty && !viewModel.hasSelfClient
                            ? ("Add yourself", { showingSelf = true })
                            : nil
                    )
                }
            }
            .themedScreen()
            .searchable(text: $viewModel.query, prompt: "Search clients")
            .navigationTitle("Clients")
            .toolbar {
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                if pendingIntake != nil { showingIntakeOffer = true }
            }) {
                ClientEditView(repo: viewModel.repository, existing: nil, onCreated: { pendingIntake = $0 }) {
                    Task { await viewModel.load() }
                }
            }
            .alert(
                "Start intake for \(pendingIntake?.name ?? "this client")?",
                isPresented: $showingIntakeOffer
            ) {
                Button("Start intake") {
                    intakeClient = pendingIntake
                    pendingIntake = nil
                }
                Button("Later", role: .cancel) { pendingIntake = nil }
            } message: {
                Text("Profile, health screening, waiver and assessments — each step can also be done later.")
            }
            .sheet(item: $intakeClient) { client in
                IntakeFlowView(
                    viewModel: IntakeFlowViewModel(
                        client: client,
                        clientRepo: viewModel.repository,
                        intake: viewModel.intake,
                        weightUnit: Unit(rawValue: defaultWeightUnit) ?? .lb
                    ),
                    onFinished: { Task { await viewModel.load() } }
                )
            }
            .sheet(isPresented: $showingSelf) {
                ClientEditView(repo: viewModel.repository, existing: nil, isSelf: true) {
                    Task { await viewModel.load() }
                }
            }
            .task {
                await viewModel.load()
                consumeSelfRequest()
            }
            .onChange(of: wantsSelfClient) { consumeSelfRequest() }
            .onChange(of: viewModel.query) {
                Task { await viewModel.load() }
            }
        }
    }

    private func consumeSelfRequest() {
        guard wantsSelfClient else { return }
        wantsSelfClient = false
        showingSelf = true
    }
}

#Preview("Clients") {
    let repos = PreviewFixtures.repositories()
    ClientListView(viewModel: ClientListViewModel(
        repo: repos.clients,
        exerciseRepo: repos.exercises,
        sessionRepo: repos.sessions,
        reporting: repos.reporting,
        reminders: repos.reminders,
        intake: repos.intake
    ))
}
