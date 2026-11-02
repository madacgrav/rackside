import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppBootstrap {
    enum State {
        case ready(ModelContainer)
        case failed(String)
    }

    private(set) var state: State
    private static let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")

    init() {
        // A snapshot left behind means the app died mid-import; it is stale now.
        SafeImporter.removeSnapshot()
        do {
            try StoreBackup.backupIfVersionChanged(storeURL: Self.storeURL, currentVersion: SchemaV2.versionString)
        } catch {
            Log.persistence.error("Pre-open backup failed: \(error.localizedDescription)")
        }
        state = Self.attempt()
    }

    /// Restore the pre-migration backup and retry (see StoreBackup).
    func restoreBackupAndRetry() {
        do {
            try StoreBackup.restoreLatest(storeURL: Self.storeURL)
        } catch {
            Log.persistence.error("Backup restore failed: \(error.localizedDescription)")
        }
        state = Self.attempt()
    }

    /// Last resort: delete the store files and start fresh; the trainer can
    /// then re-import an export file from Settings.
    func resetStoreAndRetry() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(filePath: Self.storeURL.path + suffix)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
            } catch {
                Log.persistence.error("Store reset could not remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        state = Self.attempt()
    }

    private static func attempt() -> State {
        do {
            return .ready(try PersistenceController.makeContainer())
        } catch {
            Log.persistence.error("ModelContainer open failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
}

@main
struct TrainMeApp: App {
    @State private var bootstrap = AppBootstrap()
    @State private var timers = TimerStore()

    var body: some Scene {
        WindowGroup {
            switch bootstrap.state {
            case .ready(let container):
                LockGateView {
                    RootView(container: container)
                }
                .environment(timers)
                .sensoryFeedback(.warning, trigger: timers.completionTick)
            case .failed(let message):
                RecoveryView(
                    message: message,
                    onRestoreBackup: { bootstrap.restoreBackupAndRetry() },
                    onReset: { bootstrap.resetStoreAndRetry() }
                )
            }
        }
    }
}

struct RecoveryView: View {
    let message: String
    let onRestoreBackup: () -> Void
    let onReset: () -> Void
    @State private var confirmingReset = false

    var body: some View {
        HeroScreen(
            systemImage: "exclamationmark.triangle.fill",
            title: "TrainMe couldn't open its data store",
            message: message,
            tint: Theme.Colors.warning,
            primary: ("Restore last backup", onRestoreBackup)
        ) {
            Button("Start fresh (then import an export file)", role: .destructive) {
                confirmingReset = true
            }
        }
        .alert("Delete the data store?", isPresented: $confirmingReset) {
            Button("Delete and start fresh", role: .destructive) { onReset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only do this if restoring the backup didn't work. You can re-import a JSON export from Settings afterwards.")
        }
    }
}
