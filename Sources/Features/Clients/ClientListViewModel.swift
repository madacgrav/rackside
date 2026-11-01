import Foundation
import Observation

@MainActor
@Observable
final class ClientListViewModel {
    let repository: any ClientRepository
    let exerciseRepo: any ExerciseRepository
    let sessionRepo: any SessionRepository
    let reporting: any ReportingQueries
    let reminders: ReminderCoordinator
    let intake: IntakeRepositories
    var clients: [ClientDTO] = []
    var query: String = ""
    var isLoading = false
    /// Hides the "Add yourself" offer once a self profile exists.
    var hasSelfClient = false

    init(
        repo: any ClientRepository,
        exerciseRepo: any ExerciseRepository,
        sessionRepo: any SessionRepository,
        reporting: any ReportingQueries,
        reminders: ReminderCoordinator,
        intake: IntakeRepositories
    ) {
        self.repository = repo
        self.exerciseRepo = exerciseRepo
        self.sessionRepo = sessionRepo
        self.reporting = reporting
        self.reminders = reminders
        self.intake = intake
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        clients = (try? await repository.search(query)) ?? []
        hasSelfClient = ((try? await repository.selfClient()) ?? nil) != nil
    }
}
