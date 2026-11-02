import SwiftUI

@main
struct TrainMeWatchApp: App {
    @State private var model = WatchTimerModel()

    var body: some Scene {
        WindowGroup {
            TimerScreen()
                .environment(model)
                .task { model.activate() }
        }
    }
}
