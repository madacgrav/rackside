import Foundation
import Observation

enum IntakeStep: Int, CaseIterable, Identifiable {
    case sections, profile, health, waiver, measurements, movement, review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sections: "Choose sections"
        case .profile: "Profile"
        case .health: "Health screening"
        case .waiver: "Waiver"
        case .measurements: "Measurements"
        case .movement: "Movement"
        case .review: "Review"
        }
    }
}

/// Which parts of the intake to run (not persisted).
struct IntakeSections: OptionSet, Sendable {
    let rawValue: Int
    static let health = IntakeSections(rawValue: 1 << 0)
    static let waiver = IntakeSections(rawValue: 1 << 1)
    static let measurements = IntakeSections(rawValue: 1 << 2)
    static let overheadSquat = IntakeSections(rawValue: 1 << 3)
    static let singleLegSquat = IntakeSections(rawValue: 1 << 4)
    static let all: IntakeSections = [.health, .waiver, .measurements, .overheadSquat, .singleLegSquat]

    var assessmentSections: AssessmentSections {
        var result: AssessmentSections = []
        if contains(.measurements) { result.insert(.measurements) }
        if contains(.overheadSquat) { result.insert(.overheadSquat) }
        if contains(.singleLegSquat) { result.insert(.singleLegSquat) }
        return result
    }
}

/// Guided new-client intake: each step reuses an existing editor's view model
/// and saves on Next, so a cancelled intake keeps the steps already done.
@MainActor
@Observable
final class IntakeFlowViewModel {
    let client: ClientDTO
    var sections: IntakeSections = .all {
        didSet { assessment.sections = sections.assessmentSections }
    }
    private(set) var index = 0
    let profile: ClientEditViewModel
    let health: HealthScreeningEditViewModel
    let waiver: ClientWaiverViewModel
    let assessment: AssessmentEditViewModel
    var errorMessage: String?

    init(client: ClientDTO, clientRepo: any ClientRepository, intake: IntakeRepositories, weightUnit: Unit) {
        self.client = client
        profile = ClientEditViewModel(repo: clientRepo, existing: client)
        health = HealthScreeningEditViewModel(repo: intake.health, clientId: client.id, existing: nil)
        waiver = ClientWaiverViewModel(repo: intake.waivers, clientRepo: clientRepo, client: client)
        assessment = AssessmentEditViewModel(
            repo: intake.assessments, clientId: client.id, existing: nil,
            sections: IntakeSections.all.assessmentSections, weightUnit: weightUnit
        )
    }

    /// Profile and review always run; the rest follow the toggles.
    nonisolated static func steps(for sections: IntakeSections) -> [IntakeStep] {
        var steps: [IntakeStep] = [.sections, .profile]
        if sections.contains(.health) { steps.append(.health) }
        if sections.contains(.waiver) { steps.append(.waiver) }
        if sections.contains(.measurements) { steps.append(.measurements) }
        if sections.contains(.overheadSquat) || sections.contains(.singleLegSquat) { steps.append(.movement) }
        steps.append(.review)
        return steps
    }

    var steps: [IntakeStep] { Self.steps(for: sections) }
    var current: IntakeStep { steps[min(index, steps.count - 1)] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { current == .review }
    var progress: Double { Double(index + 1) / Double(steps.count) }

    /// Saves the current step (if it has a draft), then advances. False when the save failed.
    func next() async -> Bool {
        errorMessage = nil
        let saved: Bool
        switch current {
        case .profile:
            guard profile.canSave else {
                errorMessage = "Check the highlighted fields before continuing."
                return false
            }
            saved = await profile.save()
            if !saved { errorMessage = profile.errorMessage }
        case .health:
            saved = await health.save()
            if !saved { errorMessage = health.errorMessage }
        case .measurements, .movement:
            saved = await assessment.save()
            if !saved { errorMessage = assessment.errorMessage }
        case .sections, .waiver, .review:
            saved = true
        }
        if saved, index < steps.count - 1 { index += 1 }
        return saved
    }

    func back() {
        errorMessage = nil
        if index > 0 { index -= 1 }
    }

    /// True when a step that is part of this intake has edits not yet saved.
    var hasUnsavedEdits: Bool {
        let steps = steps
        return (steps.contains(.profile) && profile.isDirty)
            || (steps.contains(.health) && health.isDirty)
            || ((steps.contains(.measurements) || steps.contains(.movement)) && assessment.isDirty)
    }
}
