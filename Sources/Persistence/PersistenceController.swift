import Foundation
import SwiftData

enum PersistenceController {
    /// Kept for callers/tests that enumerate the model types.
    static var schemaTypes: [any PersistentModel.Type] { SchemaV3.models }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // Application Support may not exist on first launch; the store lives there.
            do {
                try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            } catch {
                Log.persistence.error("createDirectory failed: \(error.localizedDescription)")
            }
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(versionedSchema: SchemaV3.self),
            migrationPlan: TrainMeMigrationPlan.self,
            configurations: config
        )
    }
}
