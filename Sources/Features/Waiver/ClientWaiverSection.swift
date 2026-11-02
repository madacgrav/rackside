import SwiftUI

/// Waiver status and actions for one client; used on client detail and in the intake flow.
struct ClientWaiverSection: View {
    @Bindable var viewModel: ClientWaiverViewModel
    @State private var returning: WaiverRecordDTO?
    @State private var returnedOn = Date.now

    var body: some View {
        Section {
            statusRow
            Button {
                Task { await viewModel.preparePDF() }
            } label: {
                Label { Text("Send waiver…") } icon: { IconBadge(systemImage: "doc.text.fill", color: Theme.Fills.magenta) }
            }
            if let record = viewModel.awaitingSignature {
                Button("Mark signed & returned…", systemImage: "checkmark.seal") {
                    returnedOn = .now
                    returning = record
                }
            }
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.octagon.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Colors.danger)
            }
            if !viewModel.records.isEmpty {
                DisclosureGroup("History") {
                    ForEach(viewModel.records) { record in
                        historyRow(record)
                            .swipeActions {
                                if record.returnedSignedOn != nil {
                                    Button("Clear signed") {
                                        Task { await viewModel.markReturned(record, on: nil) }
                                    }
                                }
                            }
                    }
                }
            }
        } header: {
            Text("Waiver")
        } footer: {
            Text("The client signs the PDF outside the app and returns it; then mark it signed here.")
        }
        .sheet(item: $viewModel.prepared) { pdf in
            ActivityShareSheet(items: [pdf.url]) { completed in
                Task { await viewModel.shareFinished(completed: completed) }
            }
        }
        .sheet(item: $returning) { record in
            NavigationStack {
                Form {
                    DatePicker("Returned on", selection: $returnedOn, in: record.sentOn...Date.now, displayedComponents: .date)
                }
                .navigationTitle("Signed & returned")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { returning = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let date = returnedOn
                            returning = nil
                            Task { await viewModel.markReturned(record, on: date) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch viewModel.status {
        case .none:
            Label("No waiver sent", systemImage: "doc.text")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        case .sent(let date):
            Label("Sent \(Self.day(date)) — awaiting signature", systemImage: "clock")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.warning)
        case .signed(let date):
            Label("Signed — returned \(Self.day(date))", systemImage: "checkmark.seal.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.success)
        }
    }

    private func historyRow(_ record: WaiverRecordDTO) -> some View {
        TitleCaptionRow(
            title: "Sent \(Self.day(record.sentOn)) · v\(record.templateVersion)",
            caption: record.returnedSignedOn.map { "Returned \(Self.day($0))" } ?? "Not returned"
        )
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview("Waiver section") {
    let repos = PreviewFixtures.repositories()
    List {
        ClientWaiverSection(viewModel: ClientWaiverViewModel(
            repo: repos.intake.waivers, clientRepo: repos.clients, client: PreviewFixtures.client
        ))
    }
}
