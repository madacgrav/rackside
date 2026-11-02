import SwiftUI

/// Settings screen for the liability-waiver template.
struct WaiverTemplateEditView: View {
    let repo: any WaiverRepository
    @State private var template: WaiverTemplateDTO?
    @State private var draft = ""
    @State private var confirmingReset = false
    @State private var errorMessage: String?

    private var isChanged: Bool { template.map { $0.body != draft } ?? false }

    // Deliberately not a Form: a TextEditor (itself a scroll view) inside a List
    // hung the app on device in a safe-area layout loop, so the editor is the
    // screen's only scroll view.
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(
                "This template is not legal advice. Waiver rules vary by state — have it reviewed by your attorney or insurer before use.",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.callout)
            .foregroundStyle(Theme.Colors.warning)
            Text(template.map { "Template v\($0.version)" } ?? "Template")
                .font(.headline)
            TextEditor(text: $draft)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                .frame(maxHeight: .infinity)
            Text("Lines in ALL CAPS become headings; start a line with !! to make it bold; lines starting with # are hidden.")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(Theme.Colors.danger)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedScreen()
        .navigationTitle("Liability Waiver")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isChanged)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Reset to starter text", role: .destructive) { confirmingReset = true }
            }
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
