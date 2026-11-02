import Foundation
import Testing
@testable import TrainMe

actor FakeWatchSync: WatchSyncing {
    private(set) var sent: [TimerSnapshot] = []
    private(set) var activated = false

    func activate() async { activated = true }
    func send(_ snapshot: TimerSnapshot) async { sent.append(snapshot) }
}

@MainActor
private func makeStore(_ sync: FakeWatchSync, defaults: UserDefaults = isolatedDefaults()) -> TimerStore {
    let clock = TestClock()
    return TimerStore(defaults: defaults, notifier: FakeTimerNotifier(), sync: sync,
                      autoComplete: false, now: { clock.now })
}

@MainActor
@Test func startSendsSnapshotWithTimer() async {
    let sync = FakeWatchSync()
    let store = makeStore(sync)
    store.startRest(seconds: 90)
    await store.flush()
    #expect(await sync.sent.last?.timer?.id == store.active?.id)
}

@MainActor
@Test func skipSendsSnapshotWithNilTimer() async {
    let sync = FakeWatchSync()
    let store = makeStore(sync)
    store.startRest(seconds: 90)
    store.skip()
    await store.flush()
    #expect(await sync.sent.count == 2)
    #expect(await sync.sent.last?.timer == nil)
}

@MainActor
@Test func snapshotCarriesDefaultRestFromDefaults() {
    let defaults = isolatedDefaults()
    defaults.set(60, forKey: TimerSettings.defaultRestKey)
    let store = makeStore(FakeWatchSync(), defaults: defaults)
    #expect(store.snapshot().defaultRest == 60)
    #expect(store.snapshot().quickPicks == TimerMath.quickPicks)
}

@MainActor
@Test func activateSyncSendsInitialSnapshot() async {
    let sync = FakeWatchSync()
    let store = makeStore(sync)
    await store.activateSync()
    await store.flush()
    #expect(await sync.activated)
    #expect(await sync.sent.count == 1)
}
