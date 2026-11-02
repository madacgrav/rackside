import Foundation

/// The next timed set the phone offers to the watch as a one-tap countdown.
struct UpNext: Codable, Sendable, Equatable {
    let plannedEntryId: UUID
    let instanceId: UUID
    let exerciseName: String
    let seconds: Int
}
