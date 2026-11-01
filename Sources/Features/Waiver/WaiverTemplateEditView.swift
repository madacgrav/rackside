import SwiftUI

/// Settings screen for the liability-waiver template.
struct WaiverTemplateEditView: View {
    let repo: any WaiverRepository
    @State private var template: WaiverTemplateDTO?
    @State private var draft = ""
    @State private var confirmingReset = false
    @State private var errorMessage: String?

    private var isChanged: Bool { template.map { $0.body != draft } ?? false }

    var body: some View {
        Form {
            Section {
                Label(
                    "This template is not legal advice. Waiver rules vary by state — have it reviewed by your attorney or insurer before use.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .foregroundStyle(Theme.Colors.warning)
            }
            Section {
                TextEditor(text: $draft)
                    .frame(minHeight: 360)
                    .font(.callout)
            } header: {
                Text(template.map { "Template v\($0.version)" } ?? "Template")
            } footer: {
                Text("Lines in ALL CAPS become headings; start a line with !! to make it bold; lines starting with # are hidden.")
                    .font(.footnote.monospaced())
            }
            Section {
                Button("Reset to starter text", role: .destructive) { confirmingReset = true }
            }
            ErrorBanner(message: errorMessage)
        }
        .navigationTitle("Liability Waiver")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Save") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isChanged)
        }
        .confirmationDialog("Replace the text with the starter template?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { draft = SwiftDataWaiverRepository.starterText() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is saved until you tap Save.")
        }
        .task {
            do {
                let loaded = try await repo.template()
                template = loaded
                draft = loaded.body
            } catch {
                errorMessage = "Couldn't load the waiver template."
            }
        }
    }

    private func save() async {
        errorMessage = nil
        do {
            template = try await repo.saveTemplate(body: draft)
        } catch {
            Log.ui.error("Waiver template save failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save the template. Please try again."
        }
    }
}

#Preview("Waiver template") {
    let repos = PreviewFixtures.repositories()
    NavigationStack {
        WaiverTemplateEditView(repo: repos.intake.waivers)
    }
}
