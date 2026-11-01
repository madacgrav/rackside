import SwiftUI

struct IntakeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: IntakeFlowViewModel
    let onFinished: () -> Void
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressView(value: viewModel.progress)
                        .accessibilityLabel("Step \(viewModel.index + 1) of \(viewModel.steps.count)")
                }
                stepContent
                ErrorBanner(message: viewModel.errorMessage)
            }
            .navigationTitle("\(viewModel.current.title) (\(viewModel.index + 1)/\(viewModel.steps.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.hasUnsavedEdits { confirmingDiscard = true } else { finish() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isLast ? "Done" : "Next") {
                        if viewModel.isLast {
                            finish()
                        } else {
                            Task { await viewModel.next() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !viewModel.isFirst {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Back", systemImage: "chevron.backward") { viewModel.back() }
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { finish() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Steps you already moved past are saved. Only this step's unsaved edits are lost.")
            }
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedEdits)
        .onDisappear { WaiverPDFRenderer.removeAll() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.current {
        case .sections:
            Section {
                sectionToggle("Health screening", .health)
                sectionToggle("Waiver", .waiver)
                sectionToggle("Measurements", .measurements)
                sectionToggle("Overhead Squat", .overheadSquat)
                sectionToggle("Single Leg Squat", .singleLegSquat)
            } header: {
                Text("Include for \(viewModel.client.name)")
            } footer: {
                Text("Profile is always included. Each part can be filled in later from the client's page.")
            }
        case .profile:
            ClientFormContent(viewModel: viewModel.profile)
        case .health:
            HealthScreeningFormContent(viewModel: viewModel.health)
        case .waiver:
            ClientWaiverSection(viewModel: viewModel.waiver)
            Section {
                Text("Send now, or skip and send later from the client's page.")
                    .foregroundStyle(.secondary)
            }
        case .measurements:
            MeasurementsFormContent(viewModel: viewModel.assessment)
        case .movement:
            MovementFormContent(viewModel: viewModel.assessment)
        case .review:
            review
        }
    }

    @ViewBuilder
    private var review: some View {
        Section("Summary") {
            LabeledContent("Profile", value: (viewModel.profile.savedClient ?? viewModel.client).hasProfile ? "Complete" : "Basic details only")
            if viewModel.sections.contains(.health) {
                ClearanceBadge(status: HealthScreeningDTO.clearance(for: viewModel.health.savedScreening))
            }
            if viewModel.sections.contains(.waiver) {
                LabeledContent("Waiver", value: waiverText)
            }
            if let assessment = viewModel.assessment.savedAssessment {
                NavigationLink {
                    AssessmentDetailView(assessment: assessment, previous: nil, weightUnit: viewModel.assessment.usesImperial ? .lb : .kg)
                } label: {
                    LabeledContent("Assessment", value: assessment.sections.caption)
                }
            }
        }
    }

    private var waiverText: String {
        switch viewModel.waiver.status {
        case .none: "Not sent"
        case .sent: "Sent — awaiting signature"
        case .signed: "Signed"
        }
    }

    private func sectionToggle(_ title: String, _ section: IntakeSections) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.sections.contains(section) },
            set: { on in
                if on { viewModel.sections.insert(section) } else { viewModel.sections.remove(section) }
            }
        ))
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}

#Preview("Intake") {
    let repos = PreviewFixtures.repositories()
    IntakeFlowView(
        viewModel: IntakeFlowViewModel(
            client: PreviewFixtures.client, clientRepo: repos.clients, intake: repos.intake, weightUnit: .lb
        ),
        onFinished: {}
    )
}
