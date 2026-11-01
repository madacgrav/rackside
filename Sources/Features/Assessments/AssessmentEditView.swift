import SwiftUI

struct AssessmentEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AssessmentEditViewModel
    private let onSaved: () -> Void

    init(repo: any AssessmentRepository, clientId: UUID, existing: AssessmentDTO?, weightUnit: Unit, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: AssessmentEditViewModel(
            repo: repo, clientId: clientId, existing: existing, weightUnit: weightUnit
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sections") {
                    sectionToggle("Measurements", .measurements)
                    sectionToggle("Overhead Squat", .overheadSquat)
                    sectionToggle("Single Leg Squat", .singleLegSquat)
                }
                Section {
                    DatePicker("Date", selection: $viewModel.performedOn, in: ...Date.now, displayedComponents: .date)
                }
                MeasurementsFormContent(viewModel: viewModel)
                MovementFormContent(viewModel: viewModel)
                ErrorBanner(message: viewModel.errorMessage)
            }
            .navigationTitle("Assessment")
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

    private func sectionToggle(_ title: String, _ section: AssessmentSections) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.sections.contains(section) },
            set: { on in
                if on { viewModel.sections.insert(section) } else { viewModel.sections.remove(section) }
            }
        ))
    }
}

/// Vitals, body and fitness numbers; shown only when Measurements is included.
struct MeasurementsFormContent: View {
    @Bindable var viewModel: AssessmentEditViewModel

    var body: some View {
        if viewModel.sections.contains(.measurements) {
            Section("Vitals") {
                OptionalStepper(label: "Resting HR (bpm)", value: $viewModel.restingHR, range: 30...220, defaultValue: 70)
                OptionalStepper(label: "Systolic BP", value: $viewModel.systolic, range: 70...250, defaultValue: 120)
                OptionalStepper(label: "Diastolic BP", value: $viewModel.diastolic, range: 40...150, defaultValue: 80)
            }
            Section("Body") {
                OptionalDecimalStepper(
                    label: "Height (\(viewModel.lengthUnit))", value: $viewModel.height,
                    range: 0...300, defaultValue: viewModel.usesImperial ? 67 : 170, step: 0.5
                )
                OptionalDecimalStepper(
                    label: "Weight (\(viewModel.massUnit))", value: $viewModel.weight,
                    range: 0...1_000, defaultValue: viewModel.usesImperial ? 170 : 77, step: 0.5
                )
                OptionalDecimalStepper(
                    label: "Waist (\(viewModel.lengthUnit))", value: $viewModel.waist,
                    range: 0...300, defaultValue: viewModel.usesImperial ? 32 : 81, step: 0.5
                )
                OptionalDecimalStepper(
                    label: "Hip (\(viewModel.lengthUnit))", value: $viewModel.hip,
                    range: 0...300, defaultValue: viewModel.usesImperial ? 38 : 97, step: 0.5
                )
                OptionalDecimalStepper(label: "Body fat (%)", value: $viewModel.bodyFatPct, range: 0...70, defaultValue: 25, step: 0.5)
                let derived = viewModel.makeDTO().measurements
                if let bmi = derived.bmi {
                    LabeledContent("BMI", value: bmi.formatted(.number.precision(.fractionLength(1))))
                }
                if let ratio = derived.waistToHip {
                    LabeledContent("Waist-to-hip", value: ratio.formatted(.number.precision(.fractionLength(2))))
                }
            }
            Section("Fitness") {
                OptionalStepper(label: "Push-ups", value: $viewModel.pushUps, range: 0...200, defaultValue: 10)
                OptionalStepper(label: "Plank (sec)", value: $viewModel.plankSeconds, range: 0...600, defaultValue: 30, step: 5)
            }
        }
    }
}

/// NASM page 1: Overhead Squat (with modified retests) and Single Leg Squat.
struct MovementFormContent: View {
    @Bindable var viewModel: AssessmentEditViewModel

    var body: some View {
        if viewModel.sections.contains(.overheadSquat) {
            Section("Overhead Squat — Anterior") {
                CompensationGrid(right: $viewModel.ohsAnteriorRight, left: $viewModel.ohsAnteriorLeft)
            }
            Section("Overhead Squat — Lateral (right side)") {
                CompensationGrid(single: $viewModel.ohsLateral)
            }
            Section("Overhead Squat — Posterior") {
                CompensationGrid(right: $viewModel.ohsPosteriorRight, left: $viewModel.ohsPosteriorLeft)
            }
            Section {
                CompensationGrid(single: $viewModel.ohsHeelsElevated)
            } header: {
                Text("Modified — Heels elevated")
            } footer: {
                Text("Mark the regions where the compensation went away.")
            }
            Section {
                CompensationGrid(single: $viewModel.ohsArmsDown)
            } header: {
                Text("Modified — Arms down")
            } footer: {
                Text("Mark the regions where the compensation went away.")
            }
            Section("Overhead Squat notes") {
                TextField("Notes", text: $viewModel.ohsNotes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        if viewModel.sections.contains(.singleLegSquat) {
            Section("Single Leg Squat") {
                CompensationGrid(right: $viewModel.slsRight, left: $viewModel.slsLeft)
            }
            Section("Single Leg Squat notes") {
                TextField("Notes", text: $viewModel.slsNotes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
    }
}

#Preview("Assessment") {
    let repos = PreviewFixtures.repositories()
    AssessmentEditView(
        repo: repos.intake.assessments, clientId: PreviewFixtures.clientId,
        existing: PreviewFixtures.assessments[0], weightUnit: .lb
    ) {}
}

#Preview("Movement only") {
    let repos = PreviewFixtures.repositories()
    Form {
        MovementFormContent(viewModel: AssessmentEditViewModel(
            repo: repos.intake.assessments, clientId: PreviewFixtures.clientId,
            existing: nil, sections: [.overheadSquat, .singleLegSquat], weightUnit: .lb
        ))
    }
}
