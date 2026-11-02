import Foundation
import SwiftData

/// Client-intake repositories, passed down together from RootView.
struct IntakeRepositories: Sendable {
    let health: any HealthScreeningRepository
    let assessments: any AssessmentRepository
    let waivers: any WaiverRepository

    init(container: ModelContainer) {
        health = SwiftDataHealthScreeningRepository(modelContainer: container)
        assessments = SwiftDataAssessmentRepository(modelContainer: container)
        waivers = SwiftDataWaiverRepository(modelContainer: container)
    }

    init(health: any HealthScreeningRepository, assessments: any AssessmentRepository, waivers: any WaiverRepository) {
        self.health = health
        self.assessments = assessments
        self.waivers = waivers
    }
}
