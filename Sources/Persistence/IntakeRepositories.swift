import Foundation
import SwiftData

/// Client-intake repositories, passed down together from RootView.
struct IntakeRepositories: Sendable {
    let health: any HealthScreeningRepository
    let assessments: any AssessmentRepository

    init(container: ModelContainer) {
        health = SwiftDataHealthScreeningRepository(modelContainer: container)
        assessments = SwiftDataAssessmentRepository(modelContainer: container)
    }

    init(health: any HealthScreeningRepository, assessments: any AssessmentRepository) {
        self.health = health
        self.assessments = assessments
    }
}
