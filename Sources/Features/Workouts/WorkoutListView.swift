import SwiftUI

struct WorkoutListView: View {
    @State var viewModel: WorkoutListViewModel
    @State private var editingWorkout: WorkoutDTO?
    @State private var showingNew = false
    @State private var pendingDelete: WorkoutDTO?

    var body: some View {
        NavigationStack {
            List {
                ErrorBanner(message: viewModel.errorMessage)
                ForEach(viewModel.workouts) { workout in
                    Button {
                        editingWorkout = workout
                    } label: {
                        TitleCaptionRow(
                            title: workout.name,
                            caption: "\(workout.entries.count) exercise\(workout.entries.count == 1 ? "" : "s")"
                        )
                    }
                    .buttonStyle(.plain)
                    .themedRows()
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = workout
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            Task { await viewModel.duplicate(id: workout.id) }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.workouts.isEmpty {
                    ProgressView()
                } else if viewModel.workouts.isEmpty {
                    EmptyState(title: "No workouts yet", area: .workouts)
                }
            }
            .themedScreen()
            .navigationTitle("Workouts")
            .toolbar {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
            .sheet(isPresented: $showingNew) {
                WorkoutBuilderView(
                    workoutRepo: viewModel.workoutRepo,
                    exerciseRepo: viewModel.exerciseRepo,
                    existing: nil
                ) {
                    Task { await viewModel.load() }
                }
            }
            .sheet(item: $editingWorkout) { workout in
                WorkoutBuilderView(
                    workoutRepo: viewModel.workoutRepo,
                    exerciseRepo: viewModel.exerciseRepo,
                    existing: workout
                ) {
                    Task { await viewModel.load() }
                }
            }
            .confirmationDialog(
                "Delete \"\(pendingDelete?.name ?? "")\"?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete workout", role: .destructive) {
                    if let id = pendingDelete?.id { Task { await viewModel.delete(id: id) } }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Scheduled sessions keep their own copy; only the template is removed.")
            }
            .task { await viewModel.load() }
        }
    }
}

#Preview("Workouts") {
    let repos = PreviewFixtures.repositories()
    WorkoutListView(viewModel: WorkoutListViewModel(
        workoutRepo: repos.workouts, exerciseRepo: repos.exercises
    ))
}
