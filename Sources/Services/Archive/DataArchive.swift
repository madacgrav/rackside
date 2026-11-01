import Foundation
import SwiftData

enum ImportMode: Sendable {
    case merge, replace
}

enum ArchiveError: Error, Equatable {
    case newerThanApp(Int)
    case unreadable
    /// Probe succeeded but the full envelope did not decode.
    case decodeFailed
}

protocol DataArchiving: Sendable {
    /// Encodes everything to a versioned JSON file in tmp; caller hands the URL
    /// to .fileExporter / ShareLink.
    func export() async throws -> URL
    /// The same archive as `export()` without touching the file system (used
    /// by SafeImporter for its pre-import snapshot).
    func exportData() async throws -> Data
    func importArchive(url: URL, mode: ImportMode) async throws
    /// Import from already-loaded data (used by tests and the recovery flow).
    func importData(_ data: Data, mode: ImportMode) async throws
}

@ModelActor
actor DataArchiveActor: DataArchiving {
    func export() async throws -> URL {
        let data = try await exportData()

        // Exports hold client PII. They live in their own tmp folder (so stale
        // ones are swept before each export and after sharing) and are written
        // with complete file protection, matching the Face ID lock on the app.
        let day = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = Self.exportsDirectory.appending(path: "TrainMe Export \(day).json")
        Self.removeExports()
        try FileManager.default.createDirectory(at: Self.exportsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func exportData() async throws -> Data {
        let envelope = CurrentArchive(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            clients: try modelContext.fetch(FetchDescriptor<Client>()).map(ClientDTO.init),
            exercises: try modelContext.fetch(FetchDescriptor<Exercise>()).map(ExerciseDTO.init),
            workouts: try modelContext.fetch(FetchDescriptor<Workout>()).map(WorkoutDTO.init),
            sessions: try modelContext.fetch(FetchDescriptor<Session>()).map(SessionDTO.init),
            setRecords: try modelContext.fetch(FetchDescriptor<SetRecord>()).map(SetRecordDTO.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static let exportsDirectory = FileManager.default.temporaryDirectory
        .appending(path: "Exports", directoryHint: .isDirectory)

    /// Deletes every export file. Call once the share/export sheet has finished.
    nonisolated static func removeExports() {
        try? FileManager.default.removeItem(at: exportsDirectory)
    }

    func importArchive(url: URL, mode: ImportMode) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.archive.error("Import file unreadable: \(error.localizedDescription)")
            throw ArchiveError.unreadable
        }
        try await importData(data, mode: mode)
    }

    func importData(_ data: Data, mode: ImportMode) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw ArchiveError.unreadable
        }
        guard probe.schemaVersion <= ArchiveV2.schemaVersion else {
            throw ArchiveError.newerThanApp(probe.schemaVersion)
        }
        // Older versions decode with their frozen envelope, then migrate forward.
        let envelope: CurrentArchive
        do {
            switch probe.schemaVersion {
            case ...1: envelope = ArchiveV2.migrate(try decoder.decode(ArchiveV1.Envelope.self, from: data))
            default: envelope = try decoder.decode(ArchiveV2.Envelope.self, from: data)
            }
        } catch {
            Log.archive.error("Envelope decode failed: \(error.localizedDescription)")
            throw ArchiveError.decodeFailed
        }

        do {
            if mode == .replace {
                try deleteAll()
            }
            try upsertAll(envelope)
            try modelContext.save()
        } catch {
            // Discard anything staged on this context so a later import does
            // not drag half-applied changes along with it.
            modelContext.rollback()
            Log.archive.error("Import (\(String(describing: mode))) failed, rolled back: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private

    private func deleteAll() throws {
        try modelContext.delete(model: SetRecord.self)
        try modelContext.delete(model: Session.self)
        try modelContext.delete(model: Workout.self)
        try modelContext.delete(model: Exercise.self)
        try modelContext.delete(model: Client.self)
    }

    /// Upsert-by-id for every entity array. Graph entities (workouts, sessions)
    /// replace their sub-graph wholesale so the archive version wins.
    private func upsertAll(_ envelope: CurrentArchive) throws {
        for dto in envelope.clients {
            let id = dto.id
            if let existing = try first(FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })) {
                dto.apply(to: existing)
            } else {
                modelContext.insert(dto.toModel())
            }
        }
        for dto in envelope.exercises {
            let id = dto.id
            if let existing = try first(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })) {
                existing.name = dto.name
                existing.categoryRaw = dto.category.rawValue
                existing.metricsRaw = dto.metrics.rawValue
                existing.defaultUnitRaw = dto.defaultUnit.rawValue
                existing.isCustom = dto.isCustom
            } else {
                modelContext.insert(dto.toModel())
            }
        }
        for dto in envelope.workouts {
            let id = dto.id
            if let existing = try first(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })) {
                modelContext.delete(existing)
            }
            let workout = Workout(id: dto.id, name: dto.name, createdAt: dto.createdAt, updatedAt: dto.updatedAt)
            modelContext.insert(workout)
            workout.entries.append(contentsOf: dto.entries.map { $0.toModel() })
        }
        for dto in envelope.sessions {
            let id = dto.id
            if let existing = try first(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })) {
                modelContext.delete(existing)
            }
            insertSessionGraph(dto)
        }
        for dto in envelope.setRecords {
            let id = dto.id
            if let existing = try first(FetchDescriptor<SetRecord>(predicate: #Predicate { $0.id == id })) {
                modelContext.delete(existing)
            }
            modelContext.insert(dto.toModel())
        }
    }

    /// Reconstructs a session with its instance graph, PRESERVING archive ids
    /// (unlike scheduling, which mints fresh ids for template copies).
    private func insertSessionGraph(_ dto: SessionDTO) {
        let session = Session(
            id: dto.id,
            clientId: dto.clientId,
            startAt: dto.startAt,
            endAt: dto.endAt,
            status: dto.status,
            notes: dto.notes,
            seriesId: dto.seriesId,
            recurrenceData: dto.recurrence.flatMap { try? JSONEncoder().encode($0) },
            eventIdentifier: dto.eventIdentifier,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        modelContext.insert(session)
        for instanceDTO in dto.instances {
            let instance = WorkoutInstance(
                id: instanceDTO.id,
                sourceWorkoutId: instanceDTO.sourceWorkoutId,
                name: instanceDTO.name
            )
            session.instances.append(instance)
            instance.plannedEntries.append(contentsOf: instanceDTO.plannedEntries.map { $0.toModel() })
        }
    }

    private func first<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> T? {
        var limited = descriptor
        limited.fetchLimit = 1
        return try modelContext.fetch(limited).first
    }
}
