#if DEBUG
import SwiftData
import SwiftUI

/// Deep screens for `-demoScreen`. The app pushes these with closure-based
/// NavigationLinks, so for screenshots each one is shown as its tab's root instead
/// (no back button). Returns nil for list screens, which the normal tab already shows.
@MainActor
enum DemoRoute {
    static func view(
        for launch: DemoLaunch, tab: Int, container: ModelContainer,
        reminders: ReminderCoordinator, intake: IntakeRepositories
    ) -> AnyView? {
        guard launch.enabled, let screen = launch.screen, screen.tab == tab else { return nil }
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let clients = SwiftDataClientRepository(modelContainer: container)
        let exercises = SwiftDataExerciseRepository(modelContainer: container)
        let workouts = SwiftDataWorkoutRepository(modelContainer: container)
        let reporting = SwiftDataReportingQueries(modelContainer: container)
        let client = DemoData.featuredClient

        switch screen {
        case .session:
            guard let session = DemoData.current.todaySession else { return nil }
            return AnyView(DemoSessionHost {
                SessionRunView(viewModel: SessionRunViewModel(
                    sessionRepo: sessions,
                    exerciseRepo: exercises,
                    clientRepo: clients,
                    session: session,
                    clientName: client.name,
                    clientPhone: client.phoneE164,
                    clientInjuries: client.injuries,
                    healthRepo: intake.health
                ), workoutRepo: workouts)
            })
        case .client:
            return AnyView(NavigationStack {
                ClientDetailView(viewModel: ClientDetailViewModel(
                    repo: clients, exerciseRepo: exercises, sessionRepo: sessions, reporting: reporting,
                    reminders: reminders, intake: intake, client: client
                ))
            })
        case .report:
            return AnyView(NavigationStack {
                ClientReportView(viewModel: ClientReportViewModel(
                    reporting: reporting, exerciseRepo: exercises, client: client
                ))
            })
        case .assessment:
            return AnyView(NavigationStack {
                AssessmentDetailView(
                    assessment: DemoData.assessments[0],
                    previous: DemoData.assessments[1],
                    weightUnit: .lb
                )
            })
        case .builder:
            return AnyView(WorkoutBuilderView(
                workoutRepo: workouts, exerciseRepo: exercises, existing: DemoData.lowerStrength
            ) {})
        case .schedule, .clients, .workouts, .exercises, .settings:
            return nil
        }
    }
}

/// Starts a rest countdown so the session screenshot shows the timer bar running.
private struct DemoSessionHost<Content: View>: View {
    @Environment(TimerStore.self) private var timers
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack { content() }
            .task { timers.startRest(seconds: 90) }
    }
}
#endif
