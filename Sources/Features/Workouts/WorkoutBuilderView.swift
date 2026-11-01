import SwiftUI

struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WorkoutBuilderViewModel
    @State private var showingPicker = false
    @State private var editingEntryIndex: Int?
    private let onSaved: () -> Void

    init(
        workoutRepo: any WorkoutRepository,
        exerciseRepo: any ExerciseRepository,
        existing: WorkoutDTO?,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: WorkoutBuilderViewModel(
            workoutRepo: workoutRepo, exerciseRepo: exerciseRepo, existing: existing
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workout name", text: $viewModel.name)
                }
                Section("Exercises") {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            editingEntryIndex = index
                        } label: {
                            TitleCaptionRow(
                                title: viewModel.exerciseNames[entry.exerciseId] ?? "Exercise",
                                caption: targetSummary(entry, unit: viewModel.exerciseUnits[entry.exerciseId] ?? .lb)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { viewModel.move(from: $0, to: $1) }
                    .onDelete { viewModel.remove(at: $0) }

                    Button("Add exercise", systemImage: "plus") { showingPicker = true }
                }
                ErrorBanner(message: viewModel.errorMessage)
            }
            .navigationTitle(viewModel.isEditing ? "Edit Workout" : "New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(repo: viewModel.exerciseRepo) { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .sheet(item: Binding(
                get: { editingEntryIndex.map { EntryIndex(value: $0) } },
                set: { editingEntryIndex = $0?.value }
            )) { wrapper in
                EntryTargetEditView(
                    entry: $viewModel.entries[wrapper.value],
                    unit: viewModel.exerciseUnits[viewModel.entries[wrapper.value].exerciseId] ?? .lb
                )
                .presentationDetents([.medium])
            }
            .task { await viewModel.loadExerciseNames() }
        }
    }

    private func targetSummary(_ entry: WorkoutEntryDTO, unit: Unit) -> String {
        var parts: [String] = []
        if let sets = entry.targetSets, let reps = entry.targetReps {
            parts.append("\(sets)×\(reps)")
        } else if let sets = entry.targetSets {
            parts.append("\(sets) sets")
        } else if let reps = entry.targetReps {
            parts.append("\(reps) reps")
        }
        if let weight = entry.targetWeight {
            parts.append("@ \(WeightFormatter.string(weight, unit: unit))")
        }
        if let duration = entry.targetDuration {
            parts.append("\(duration)s")
        }
        return parts.isEmpty ? "No targets" : parts.joined(separator: " ")
    }
}

private struct EntryIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let repo: any ExerciseRepository
    let onPick: (ExerciseDTO) -> Void

    @State private var query = ""
    @State private var results: [ExerciseDTO] = []

    var body: some View {
        NavigationStack {
            List(results) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    TitleCaptionRow(title: exercise.name, caption: exercise.category.rawValue.capitalized)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { results = (try? await repo.search(prefix: "")) ?? [] }
            .onChange(of: query) {
                Task { results = (try? await repo.search(prefix: query)) ?? [] }
            }
        }
    }
}

struct EntryTargetEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var entry: WorkoutEntryDTO
    let unit: Unit

    var body: some View {
        NavigationStack {
            Form {
                Section("Targets") {
                    OptionalStepper(label: "Sets", value: $entry.targetSets, range: 1...20, defaultValue: 3)
                    OptionalStepper(label: "Reps", value: $entry.targetReps, range: 1...100, defaultValue: 10)
                    AdaptiveLabeledRow(label: "Weight (\(WeightFormatter.label(unit)))") {
                        MetricStepper(
                            label: "Weight (\(WeightFormatter.label(unit)))",
                            value: Binding(
                                get: { entry.targetWeight ?? 0 },
                                set: { entry.targetWeight = $0 > 0 ? $0 : nil }
                            ),
                            step: WeightFormatter.stepIncrement(for: unit)
                        )
                    }
                    OptionalStepper(label: "Duration (sec)", value: $entry.targetDuration, range: 5...7200, defaultValue: 60, step: 5)
                }
            }
            .navigationTitle("Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Builder") {
    let repos = PreviewFixtures.repositories()
    WorkoutBuilderView(workoutRepo: repos.workouts, exerciseRepo: repos.exercises, existing: PreviewFixtures.workout) {}
}

#Preview("Exercise picker") {
    let repos = PreviewFixtures.repositories()
    ExercisePickerView(repo: repos.exercises) { _ in }
}
