import Foundation
import SwiftData

/// Client-intake repositories, passed down together from RootView.
struct IntakeRepositories: Sendable {
    let health: any HealthScreeningRepository

    init(container: ModelContainer) {
        health = SwiftDataHealthScreeningRepository(modelContainer: container)
    }

    init(health: any HealthScreeningRepository) {
        self.health = health
    }
}
