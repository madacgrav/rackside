import Foundation
import Testing
@testable import Rackside

@Test(arguments: [false, true], [false, true])
func phoneOwnsCueUnlessWatchCertain(installed: Bool, paired: Bool) {
    for reachable in [false, true] {
        let cue = CueState(watchAppInstalled: installed, paired: paired, reachable: reachable)
        #expect(phoneOwnsCue(cue) == !(installed && paired && reachable))
    }
}

@Test func noWatchMeansPhoneOwnsCue() {
    #expect(phoneOwnsCue(.noWatch))
}

@MainActor
private func makeStore(_ sync: FakeWatchSync, _ notifier: FakeTimerNotifier) -> TimerStore {
    let clock = TestClock()
    return TimerStore(defaults: isolatedDefaults(), notifier: notifier, sync: sync,
                      autoComplete: false, now: { clock.now })
}

@MainActor
@Test func watchOwnedCueSkipsPhoneNotification() async {
    let sync = FakeWatchSync()
    await sync.setCue(CueState(watchAppInstalled: true, paired: true, reachable: true))
    let notifier = FakeTimerNotifier()
    let store = makeStore(sync, notifier)
    store.startRest(seconds: 60)
    await store.flush()
    #expect(await notifier.scheduled.isEmpty)
    #expect(await notifier.cancelCount == 1)
}

@MainActor
@Test func unreachableWatchPhoneNotifies() async {
    let sync = FakeWatchSync()
    await sync.setCue(CueState(watchAppInstalled: true, paired: true, reachable: false))
    let notifier = FakeTimerNotifier()
    let store = makeStore(sync, notifier)
    store.startRest(seconds: 60)
    await store.flush()
    #expect(await notifier.scheduled == [store.active!.id])
}
