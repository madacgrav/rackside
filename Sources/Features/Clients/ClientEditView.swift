import SwiftUI

struct ClientEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ClientEditViewModel
    private let onSaved: () -> Void

    init(repo: any ClientRepository, existing: ClientDTO?, isSelf: Bool = false, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: ClientEditViewModel(repo: repo, existing: existing, isSelf: isSelf))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                ClientFormContent(viewModel: viewModel)
                ErrorBanner(message: viewModel.errorMessage)
            }
            .navigationTitle(viewModel.isSelf ? "About You" : (viewModel.isEditing ? "Edit Client" : "New Client"))
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

/// The client form's sections, shared by the edit sheet and the intake flow.
struct ClientFormContent: View {
    @Bindable var viewModel: ClientEditViewModel

    var body: some View {
        Section(viewModel.isSelf ? "Your profile" : "Contact") {
            TextField("Name", text: $viewModel.name)
            if !viewModel.isSelf {
                TextField("Mobile phone", text: $viewModel.phoneRaw)
                    .keyboardType(.phonePad)
                if !viewModel.phoneRaw.isEmpty && !viewModel.phoneValid {
                    Text("Enter a valid phone number")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.danger)
                }
            }
        }
        Section("Training") {
            TextField("Primary goal", text: $viewModel.goal)
            TextField("Injuries / limitations", text: $viewModel.injuries, axis: .vertical)
        }
        Section("Profile") {
            Toggle("Date of birth", isOn: $viewModel.hasDateOfBirth)
            if viewModel.hasDateOfBirth {
                DatePicker("Born", selection: $viewModel.dateOfBirth, in: ...Date.now, displayedComponents: .date)
            }
            TextField("Occupation", text: $viewModel.occupation)
            TextField("Training history", text: $viewModel.trainingHistory, axis: .vertical)
            TextField("Availability", text: $viewModel.availability, axis: .vertical)
        }
        Section("Emergency contact") {
            TextField("Name", text: $viewModel.emergencyName)
            TextField("Relationship", text: $viewModel.emergencyRelationship)
            TextField("Phone", text: $viewModel.emergencyPhoneRaw)
                .keyboardType(.phonePad)
            if !viewModel.emergencyPhoneValid {
                invalidPhoneCaption
            }
        }
        Section("Physician") {
            TextField("Name", text: $viewModel.physicianName)
            TextField("Phone", text: $viewModel.physicianPhoneRaw)
                .keyboardType(.phonePad)
            if !viewModel.physicianPhoneValid {
                invalidPhoneCaption
            }
        }
        Section("Notes") {
            TextField("Notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var invalidPhoneCaption: some View {
        Text("Enter a valid phone number")
            .font(.caption)
            .foregroundStyle(Theme.Colors.danger)
    }
}

#Preview("Edit client") {
    let repos = PreviewFixtures.repositories()
    ClientEditView(repo: repos.clients, existing: PreviewFixtures.client) {}
}

#Preview("About you") {
    let repos = PreviewFixtures.repositories()
    ClientEditView(repo: repos.clients, existing: nil, isSelf: true) {}
}
