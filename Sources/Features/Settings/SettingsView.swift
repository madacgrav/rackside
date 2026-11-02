import EventKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    let archive: any DataArchiving
    let reminders: ReminderCoordinator
    let waivers: any WaiverRepository
    var calendar: any CalendarSyncing = EventKitCalendarService()

    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastExportAt") private var lastExportAt: Double = 0
    @AppStorage("defaultWeightUnit") private var defaultWeightUnit: String = Unit.lb.rawValue
    @AppStorage(TimerSettings.defaultRestKey) private var defaultRestSeconds = TimerMath.defaultRest
    @State private var exportURL: URL?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImportURL: URL?
    @State private var showingModeDialog = false
    @State private var showingReplaceConfirm = false
    @State private var statusMessage: String?

    private var notificationStatusText: String {
        switch reminders.notificationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private var calendarStatusText: String {
        switch calendarStatus {
        case .fullAccess: "Allowed"
        case .writeOnly: "Write only"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private var lastExportText: String {
        lastExportAt == 0
            ? "Never"
            : Date(timeIntervalSince1970: lastExportAt).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Weight unit for new exercises", selection: $defaultWeightUnit) {
                        Text("lb").tag(Unit.lb.rawValue)
                        Text("kg").tag(Unit.kg.rawValue)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("Each exercise keeps its own unit; change it from the Exercises tab. Existing weights are never converted.")
                }

                Section {
                    NavigationLink("Liability waiver template") {
                        WaiverTemplateEditView(repo: waivers)
                    }
                } header: {
                    Text("Client intake")
                } footer: {
                    Text("Sent to new clients as a PDF to sign and return.")
                }

                Section {
                    Picker("Default rest", selection: $defaultRestSeconds) {
                        ForEach(TimerSettings.restChoices, id: \.self) { Text("\($0) s").tag($0) }
                    }
                } header: {
                    Text("Timers")
                } footer: {
                    Text("Logging a set starts a rest countdown of this length.")
                }

                Section {
                    Button("Export all data…", systemImage: "square.and.arrow.up") {
                        Task {
                            do {
                                exportURL = try await archive.export()
                                showingExporter = true
                            } catch {
                                Log.archive.error("Export failed: \(error.localizedDescription)")
                                statusMessage = "Export failed. Please try again."
                            }
                        }
                    }
                    Button("Import from file…", systemImage: "square.and.arrow.down") {
                        showingImporter = true
                    }
                    LabeledContent("Last export", value: lastExportText)
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Your data lives only on this iPhone. Exporting to a file is the ONLY backup — a lost or broken phone otherwise means losing everything. Export regularly and keep the file somewhere safe (iCloud Drive, email it to yourself).")
                }

                Section {
                    PermissionRow(
                        title: "Notifications",
                        status: notificationStatusText,
                        isDenied: reminders.notificationStatus == .denied
                    )
                    PermissionRow(
                        title: "Calendar",
                        status: calendarStatusText,
                        isDenied: calendarStatus == .denied || calendarStatus == .restricted
                    )
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Session reminders fire 24 hours and 1 hour before each session. Calendar access is only needed when you add a session to your calendar.")
                }

                Section {
                    LabeledContent("Version", value: AppInfo.versionString())
                    Link("User guide", destination: AppLinks.guide)
                    Link("What's new", destination: AppLinks.changelog)
                    Link("Privacy policy", destination: AppLinks.privacy)
                    Link("Support", destination: AppLinks.support)
                    Link("License (GPL v3)", destination: AppLinks.license)
                } header: {
                    Text("About")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage).foregroundStyle(.secondary)
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Settings")
            .task { await refreshPermissions() }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from the system Settings app must refresh the rows.
                if phase == .active {
                    Task { await refreshPermissions() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                item: exportURL,
                contentTypes: [.json],
                defaultFilename: exportURL?.lastPathComponent
            ) { result in
                switch result {
                case .success:
                    lastExportAt = Date.now.timeIntervalSince1970
                    statusMessage = "Export saved."
                case .failure(let error):
                    Log.archive.error("Export sheet failed: \(error.localizedDescription)")
                    statusMessage = "Export wasn't saved."
                }
                // The export file holds client PII: never leave it in tmp.
                exportURL = nil
                DataArchiveActor.removeExports()
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    pendingImportURL = url
                    showingModeDialog = true
                case .failure(let error):
                    Log.archive.error("Import picker failed: \(error.localizedDescription)")
                    statusMessage = "Couldn't open that file."
                }
            }
            .confirmationDialog("How should the import be applied?", isPresented: $showingModeDialog, titleVisibility: .visible) {
                Button("Merge with existing data") {
                    Task { await runImport(mode: .merge) }
                }
                Button("Replace ALL data", role: .destructive) {
                    showingReplaceConfirm = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Replace everything?", isPresented: $showingReplaceConfirm) {
                Button("Replace", role: .destructive) {
                    Task { await runImport(mode: .replace) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All current clients, workouts, sessions and history will be deleted and replaced by the file's contents. This cannot be undone.")
            }
        }
    }

    private func refreshPermissions() async {
        await reminders.refreshPermissionStatus()
        calendarStatus = await calendar.authorizationStatus()
    }

    private func runImport(mode: ImportMode) async {
        guard let url = pendingImportURL else { return }
        defer { pendingImportURL = nil }
        do {
            switch mode {
            case .merge:
                try await archive.importArchive(url: url, mode: .merge)
            case .replace:
                try await SafeImporter(archive: archive).importReplacing(url: url)
            }
            statusMessage = "Import complete."
        } catch ArchiveError.newerThanApp {
            statusMessage = "This file was exported by a newer version of Rackside. Update the app first."
        } catch ArchiveError.unreadable {
            statusMessage = "Import failed: the file couldn't be read."
        } catch ArchiveError.decodeFailed {
            statusMessage = "Import failed: the file isn't a valid Rackside export."
        } catch let outcome as ImportOutcome {
            switch outcome {
            case .failedAndRestored:
                statusMessage = "Import failed. Your previous data was restored."
            case .failedAndRestoreFailed:
                statusMessage = "Import failed and your data may be incomplete. Re-import your last export now."
            }
        } catch {
            Log.archive.error("Import failed: \(error.localizedDescription)")
            statusMessage = "Import failed. Please try again."
        }
    }
}

/// One row of the Permissions section: status text plus a deep link when denied.
struct PermissionRow: View {
    let title: String
    let status: String
    let isDenied: Bool

    var body: some View {
        HStack {
            LabeledContent(title, value: status)
            if isDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.footnote)
            }
        }
    }
}

#Preview("Settings") {
    let repos = PreviewFixtures.repositories()
    SettingsView(archive: repos.archive, reminders: repos.reminders, waivers: repos.intake.waivers)
}
