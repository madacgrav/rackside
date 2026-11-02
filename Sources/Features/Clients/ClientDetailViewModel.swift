import Foundation
import Observation

@MainActor
@Observable
final class ClientDetailViewModel {
    let repository: any ClientRepository
    let exerciseRepo: any ExerciseRepository
    let sessionRepo: any SessionRepository
    let reporting: any ReportingQueries
    let reminders: ReminderCoordinator
    let intake: IntakeRepositories
    var client: ClientDTO
    /// Scheduled sessions that have not started yet, soonest first.
    var upcomingSessions: [SessionDTO] = []
    /// Everything else (past or resolved), most recent first.
    var recentSessions: [SessionDTO] = []
    /// Newest first; the first one drives clearance and the review prompt.
    var screenings: [HealthScreeningDTO] = []
    /// Newest first.
    var assessments: [AssessmentDTO] = []
    var errorMessage: String?

    var clearance: ClearanceStatus { HealthScreeningDTO.clearance(for: screenings.first) }
    var screeningReviewDue: Bool { HealthScreeningDTO.reviewDue(screenings.first, now: .now) }

    static let recentLimit = 10

    init(
        repo: any ClientRepository,
        exerciseRepo: any ExerciseRepository,
        sessionRepo: any SessionRepository,
        reporting: any ReportingQueries,
        reminders: ReminderCoordinator,
        intake: IntakeRepositories,
        client: ClientDTO
    ) {
        self.repository = repo
        self.exerciseRepo = exerciseRepo
        self.sessionRepo = sessionRepo
        self.reporting = reporting
        self.reminders = reminders
        self.intake = intake
        self.client = client
    }

    func reload() async {
        do {
            if let refreshed = try await repository.allIncludingArchived().first(where: { $0.id == client.id }) {
                client = refreshed
            }
        } catch {
            Log.ui.debug("client refresh failed: \(error.localizedDescription)")
        }
        let all: [SessionDTO]  // newest first
        do {
            all = try await sessionRepo.forClient(client.id)
        } catch {
            Log.ui.debug("client sessions load failed: \(error.localizedDescription)")
            all = []
        }
        let now = Date.now
        let split = Self.splitSessions(all, now: now)
        upcomingSessions = split.upcoming
        recentSessions = split.recent
        do {
            screenings = try await intake.health.forClient(client.id)
        } catch {
            Log.ui.debug("client screenings load failed: \(error.localizedDescription)")
            screenings = []
        }
        do {
            assessments = try await intake.assessments.forClient(client.id)
        } catch {
            Log.ui.debug("client assessments load failed: \(error.localizedDescription)")
            assessments = []
        }
        // Status changes made from this screen must re-plan trainer alerts too.
        await reminders.refresh()
    }

    /// Pure split so the ordering rules are testable without a store.
    static func splitSessions(_ sessions: [SessionDTO], now: Date) -> (upcoming: [SessionDTO], recent: [SessionDTO]) {
        let upcoming = sessions
            .filter { $0.status == .scheduled && $0.startAt > now }
            .sorted { $0.startAt < $1.startAt }
        let recent = sessions
            .filter { !($0.status == .scheduled && $0.startAt > now) }
            .sorted { $0.startAt > $1.startAt }
            .prefix(recentLimit)
        return (upcoming, Array(recent))
    }

    func toggleArchived() async {
        errorMessage = nil
        do {
            try await repository.setArchived(id: client.id, !client.isArchived)
        } catch {
            Log.ui.error("setArchived failed: \(error.localizedDescription)")
            errorMessage = "Couldn't update the client."
        }
        await reload()
    }
}
