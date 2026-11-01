import SwiftUI

struct ClientListView: View {
    @State var viewModel: ClientListViewModel
    @State private var showingAdd = false
    @State private var showingSelf = false
    /// Set by the first-run notice in RootView; consumed once to open the self sheet.
    @AppStorage("wantsSelfClient") private var wantsSelfClient = false

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
            .sheet(isPresented: $showingAdd) {
                ClientEditView(repo: viewModel.repository, existing: nil) {
                    Task { await viewModel.load() }
                }
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
