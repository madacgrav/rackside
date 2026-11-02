import SwiftUI

struct HealthScreeningEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HealthScreeningEditViewModel
    private let onSaved: () -> Void

    init(repo: any HealthScreeningRepository, clientId: UUID, existing: HealthScreeningDTO?, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: HealthScreeningEditViewModel(repo: repo, clientId: clientId, existing: existing))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                HealthScreeningFormContent(viewModel: viewModel)
                ErrorBanner(message: viewModel.errorMessage)
            }
            .navigationTitle("Health Screening")
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
        }
    }
}

/// The screening form's sections, shared by the edit sheet and the intake flow.
struct HealthScreeningFormContent: View {
    @Bindable var viewModel: HealthScreeningEditViewModel

    var body: some View {
        Section("Screening") {
            DatePicker("Completed", selection: $viewModel.completedOn, in: ...Date.now, displayedComponents: .date)
        }
        Section {
            ForEach(ScreeningAnswers.questions, id: \.0.rawValue) { question, text in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(text)
                    Picker(text, selection: Binding(
                        get: { viewModel.isYes(question) },
                        set: { viewModel.set(question, $0) }
                    )) {
                        Text("No").tag(false)
                        Text("Yes").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        } header: {
            Text("Questions")
        } footer: {
            Text("Any YES means medical clearance is recommended before training. This screening is not a diagnosis.")
        }
        if viewModel.anyYes {
            Section("Clearance") {
                Toggle("Clearance received", isOn: $viewModel.hasClearance)
                if viewModel.hasClearance {
                    DatePicker("Received", selection: $viewModel.clearanceReceivedOn, in: ...Date.now, displayedComponents: .date)
                }
            }
        }
        Section("Medical history") {
            TextField("Conditions", text: $viewModel.conditions, axis: .vertical)
            TextField("Surgeries", text: $viewModel.surgeries, axis: .vertical)
            TextField("Medications and supplements", text: $viewModel.medications, axis: .vertical)
            Toggle("Family history of heart disease before 55 (men) / 65 (women)", isOn: $viewModel.familyHeartHistory)
            TextField("Symptoms (chest pain, breathlessness, fainting, swelling)", text: $viewModel.symptoms, axis: .vertical)
        }
        Section("Lifestyle") {
            OptionalDecimalStepper(label: "Sleep (hours)", value: $viewModel.sleepHours, range: 0...14, defaultValue: 7, step: 0.5)
            Picker("Stress", selection: $viewModel.stressLevel) {
                Text("Not recorded").tag(0)
                ForEach(1...5, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            Toggle("Uses tobacco", isOn: $viewModel.tobacco)
            OptionalStepper(label: "Drinks per week", value: $viewModel.alcoholPerWeek, range: 0...50, defaultValue: 0)
            Picker("Activity level", selection: $viewModel.activityLevel) {
                Text("Not recorded").tag(ActivityLevel?.none)
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(ActivityLevel?.some(level))
                }
            }
        }
        Section("Notes") {
            TextField("Notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }
}

#Preview("Health screening") {
    let repos = PreviewFixtures.repositories()
    HealthScreeningEditView(repo: repos.intake.health, clientId: PreviewFixtures.clientId, existing: PreviewFixtures.screening) {}
}
