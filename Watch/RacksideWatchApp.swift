import SwiftUI

@main
struct RacksideWatchApp: App {
    @State private var model: WatchTimerModel = {
        #if DEBUG
        if let snapshot = WatchDemo.snapshot() { return WatchTimerModel(snapshot: snapshot) }
        #endif
        return WatchTimerModel()
    }()

    private var isDemo: Bool {
        #if DEBUG
        WatchDemo.snapshot() != nil
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TimerScreen()
                .environment(model)
                .task {
                    // Demo screenshots must not be overwritten by a phone snapshot.
                    if !isDemo { model.activate() }
                }
        }
    }
}
