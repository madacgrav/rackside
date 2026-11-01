import SwiftData
import Testing
@testable import TrainMe

@Test func schemaV1ListsAllModels() {
    #expect(SchemaV1.models.count == 8)
    #expect(SchemaV1.versionString == "1.0.0")
    #expect(SchemaV2.models.count == 8)
    #expect(SchemaV2.versionString == "2.0.0")
    #expect(SchemaV3.models.count == 9)
    #expect(SchemaV3.versionString == "3.0.0")
    #expect(TrainMeMigrationPlan.schemas.count == 3)
    #expect(TrainMeMigrationPlan.stages.count == 2)
}

@Test func containerOpensThroughMigrationPlan() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    #expect(container.schema.entities.count == 9)
}
