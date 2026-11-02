#if DEBUG
import Foundation

/// Screens the demo launch can open directly, for App Store and guide screenshots.
enum DemoScreen: String, CaseIterable, Sendable {
    case schedule, session, clients, client, report, assessment, workouts, builder, exercises, settings

    /// RootView tab that hosts this screen.
    var tab: Int {
        switch self {
        case .schedule, .session: 0
        case .clients, .client, .report, .assessment: 1
        case .workouts, .builder: 2
        case .exercises: 3
        case .settings: 4
        }
    }
}

/// Debug-only launch flags: `-demoData` swaps in an in-memory sample dataset and
/// skips the lock; `-demoScreen <name>` picks the starting screen.
struct DemoLaunch: Sendable, Equatable {
    let enabled: Bool
    let screen: DemoScreen?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        enabled = arguments.contains("-demoData")
        if let i = arguments.firstIndex(of: "-demoScreen"), arguments.indices.contains(i + 1) {
            screen = DemoScreen(rawValue: arguments[i + 1])
        } else {
            screen = nil
        }
    }

    static let current = DemoLaunch()
}
#endif
