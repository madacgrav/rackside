import SwiftData
import SwiftUI

struct RootView: View {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenBackupNotice") private var hasSeenBackupNotice = false
    @AppStorage("lastExportAt") private var lastExportAt: Double = 0
    @AppStorage("wantsSelfClient") private var wantsSelfClient = false
    @State private var selectedTab = 0
    @State private var exportDue = false
    @State private var seedFailed = false
    @State private var reminders: ReminderCoordinator
    private let intake: IntakeRepositories

    init(container: ModelContainer) {
        self.container = container
        intake = IntakeRepositories(container: container)
        _reminders = State(initialValue: ReminderCoordinator(
            sessionRepo: SwiftDataSessionRepository(modelContainer: container),
            clientRepo: SwiftDataClientRepository(modelContainer: container),
            notifications: LocalNotificationService()
        ))
    }

    private var backupNoticeBinding: Binding<Bool> {
        Binding(get: { !hasSeenBackupNotice }, set: { hasSeenBackupNotice = !$0 })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Schedule", systemImage: "calendar", value: 0) {
                ScheduleView(
                    viewModel: ScheduleViewModel(
                        sessionRepo: SwiftDataSessionRepository(modelContainer: container),
                        clientRepo: SwiftDataClientRepository(modelContainer: container),
                        workoutRepo: SwiftDataWorkoutRepository(modelContainer: container),
                        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
                        reminders: reminders,
                        healthRepo: intake.health
                    ),
                    openSettings: { selectedTab = 4 }
                )
            }
            Tab("Clients", systemImage: "person.2.fill", value: 1) {
                ClientListView(viewModel: ClientListViewModel(
                    repo: SwiftDataClientRepository(modelContainer: container),
                    exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
                    sessionRepo: SwiftDataSessionRepository(modelContainer: container),
                    reporting: SwiftDataReportingQueries(modelContainer: container),
                    reminders: reminders,
                    intake: intake
                ))
            }
            Tab("Workouts", systemImage: "list.clipboard.fill", value: 2) {
                WorkoutListView(viewModel: WorkoutListViewModel(
                    workoutRepo: SwiftDataWorkoutRepository(modelContainer: container),
                    exerciseRepo: SwiftDataExerciseRepository(modelContainer: container)
                ))
            }
            Tab("Exercises", systemImage: "dumbbell.fill", value: 3, role: .search) {
                ExerciseListView(viewModel: ExerciseListViewModel(repo: SwiftDataExerciseRepository(modelContainer: container)))
            }
            Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                SettingsView(archive: DataArchiveActor(modelContainer: container), reminders: reminders)
            }
            .badge(exportDue ? Text("!") : nil)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fontDesign(.rounded)
        .tint(Theme.Colors.accent)
        .alert("Your data lives only on this iPhone", isPresented: backupNoticeBinding) {
            Button("Got it") { hasSeenBackupNotice = true }
            Button("Add yourself as a client") {
                hasSeenBackupNotice = true
                selectedTab = 1
                wantsSelfClient = true
            }
        } message: {
            Text("There is no cloud backup in this version. Export your data regularly from Settings — an export file is the only way to recover from a lost or broken phone.")
        }
        .onChange(of: scenePhase) { _, phase in
            // `.inactive` fires during Face ID; only a real foreground matters.
            if phase == .active {
                Task {
                    await reminders.refresh()
                    exportDue = await reminders.exportReminderIsDue()
                }
            }
        }
        .onChange(of: lastExportAt) {
            // A successful export clears the badge immediately.
            Task { exportDue = await reminders.exportReminderIsDue() }
        }
        .alert("Couldn't load the exercise library", isPresented: $seedFailed) {
            Button("OK") {}
        } message: {
            Text("You can add exercises manually from the Exercises tab, or restart the app to try again.")
        }
        .task {
            let container = container
            let seeded: Bool = await Task.detached {
                do {
                    try await SeedImporter.seedIfEmpty(repo: SwiftDataExerciseRepository(modelContainer: container))
                    return true
                } catch {
                    Log.persistence.error("Seed import failed: \(error.localizedDescription)")
                    return false
                }
            }.value
            seedFailed = !seeded
            await reminders.requestAuthorization()
            exportDue = await reminders.exportReminderIsDue()
        }
    }
}
