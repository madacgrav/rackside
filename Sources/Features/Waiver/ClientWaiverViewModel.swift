import Foundation
import Observation

@MainActor
@Observable
final class ClientWaiverViewModel {
    /// A rendered PDF waiting for the share sheet.
    struct PreparedPDF: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private let repo: any WaiverRepository
    private let clientRepo: any ClientRepository
    let client: ClientDTO
    /// Newest first.
    var records: [WaiverRecordDTO] = []
    var prepared: PreparedPDF?
    var errorMessage: String?

    init(repo: any WaiverRepository, clientRepo: any ClientRepository, client: ClientDTO) {
        self.repo = repo
        self.clientRepo = clientRepo
        self.client = client
    }

    var status: WaiverStatus { WaiverRecordDTO.status(records) }
    /// The record "Mark signed & returned" applies to.
    var awaitingSignature: WaiverRecordDTO? { records.first { $0.returnedSignedOn == nil } }

    func load() async {
        do {
            records = try await repo.records(clientId: client.id)
        } catch {
            Log.ui.debug("waiver records load failed: \(error.localizedDescription)")
        }
    }

    func preparePDF() async {
        errorMessage = nil
        do {
            let template = try await repo.template()
            let trainer = try? await clientRepo.selfClient()
            let url = try WaiverPDFRenderer.render(
                body: template.body, clientName: client.name, trainerName: trainer?.name,
                version: template.version, date: .now
            )
            prepared = PreparedPDF(url: url)
        } catch {
            Log.ui.error("Waiver PDF failed: \(error.localizedDescription)")
            errorMessage = "Couldn't create the waiver PDF."
        }
    }

    /// Records the send only when the share sheet actually completed.
    func shareFinished(completed: Bool) async {
        prepared = nil
        WaiverPDFRenderer.removeAll()
        guard completed else { return }
        do {
            _ = try await repo.recordSent(clientId: client.id, on: .now)
        } catch {
            Log.ui.error("recordSent failed: \(error.localizedDescription)")
            errorMessage = "The waiver was shared but couldn't be recorded."
        }
        await load()
    }

    func markReturned(_ record: WaiverRecordDTO, on date: Date?) async {
        errorMessage = nil
        do {
            try await repo.markReturned(id: record.id, on: date)
        } catch {
            Log.ui.error("markReturned failed: \(error.localizedDescription)")
            errorMessage = "Couldn't update the waiver."
        }
        await load()
    }
}
