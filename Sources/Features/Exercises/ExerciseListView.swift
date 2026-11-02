import SwiftUI

struct ExerciseListView: View {
    @State var viewModel: ExerciseListViewModel
    @State private var showingAdd = false
    @State private var editingExercise: ExerciseDTO?

    var body: some View {
        NavigationStack {
            List(viewModel.filtered) { exercise in
                Button {
                    editingExercise = exercise
                } label: {
                    TitleCaptionRow(title: exercise.name, caption: exercise.category.rawValue.capitalized) {
                        if exercise.isCustom {
                            Text("Custom")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .themedRows()
            }
            .overlay {
                if viewModel.isLoading && viewModel.filtered.isEmpty {
                    ProgressView()
                } else if viewModel.filtered.isEmpty {
                    EmptyState(title: "No exercises", area: .exercises)
                }
            }
            .themedScreen()
            .searchable(text: $viewModel.query, prompt: "Search exercises")
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Category", selection: $viewModel.categoryFilter) {
                        Text("All").tag(ExerciseCategory?.none)
                        ForEach(ExerciseCategory.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(ExerciseCategory?.some(category))
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ExerciseEditView(repo: viewModel.repository) {
                    Task { await viewModel.load() }
                }
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditView(repo: viewModel.repository, existing: exercise) {
                    Task { await viewModel.load() }
                }
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.query) {
                Task { await viewModel.load() }
            }
        }
    }
}

#Preview("Exercises") {
    let repos = PreviewFixtures.repositories()
    ExerciseListView(viewModel: ExerciseListViewModel(repo: repos.exercises))
}
