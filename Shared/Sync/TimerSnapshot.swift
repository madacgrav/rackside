import Foundation

/// Phone → watch state. The newest `sentAt` wins on the watch.
struct TimerSnapshot: Codable, Sendable, Equatable {
    var timer: ActiveTimer?
    var upNext: UpNext?
    var defaultRest: Int
    var quickPicks: [Int]
    var sentAt: Date
}
