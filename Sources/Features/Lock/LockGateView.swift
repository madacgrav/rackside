import SwiftUI

/// Gates the app behind biometric auth. Locks on `.background` only — Face ID's
/// own system UI briefly drops the app to `.inactive`, which must NOT re-lock.
struct LockGateView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = AppLock()
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if isUnlocked {
                content()
            } else {
                lockScreen
            }
        }
        .task {
            #if DEBUG
            if DemoLaunch.current.enabled { return }
            #endif
            await lock.authenticate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                lock.lock()
            case .active:
                if !lock.isUnlocked {
                    Task { await lock.authenticate() }
                }
            default:
                break
            }
        }
    }

    private var isUnlocked: Bool {
        #if DEBUG
        if DemoLaunch.current.enabled { return true }
        #endif
        return lock.isUnlocked
    }

    private var lockScreen: some View {
        HeroScreen(
            systemImage: "lock.fill",
            title: "TrainMe is locked",
            primary: ("Unlock", { Task { await lock.authenticate() } })
        )
    }
}
