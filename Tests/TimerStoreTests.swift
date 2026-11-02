import Foundation
import Testing
@testable import TrainMe

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

actor FakeTimerNotifier: TimerNotifying {
    private(set) var scheduled: [UUID] = []
    private(set) var cancelCount = 0

    func schedule(_ timer: ActiveTimer) async { scheduled.append(timer.id) }
    func cancelAll() async { cancelCount += 1 }
}

func isolatedDefaults() -> UserDefaults { UserDefaults(suiteName: "timer-\(UUID())")! }

@MainActor
private func makeStore(
    _ clock: TestClock,
    defaults: UserDefaults = isolatedDefaults(),
    notifier: FakeTimerNotifier = FakeTimerNotifier()
) -> TimerStore {
    TimerStore(defaults: defaults, notifier: notifier, autoComplete: false, now: { clock.now })
}

@MainActor
@Test func startRestSetsEndFromNow() {
    let clock = TestClock()
    let store = makeStore(clock)
    store.startRest(seconds: 90)
    #expect(store.active?.endAt == clock.now.addingTimeInterval(90))
    #expect(store.active?.kind == .rest)
}

@MainActor
@Test func refreshBeforeEndDoesNothing() {
    let clock = TestClock()
    let store = makeStore(clock)
    store.startRest(seconds: 90)
    clock.advance(89)
    store.refresh()
    #expect(store.active != nil)
    #expect(store.completionTick == 0)
}

@MainActor
@Test func refreshAfterEndCompletes() {
    let clock = TestClock()
    let store = makeStore(clock)
    store.startRest(seconds: 90)
    clock.advance(90)
    store.refresh()
    #expect(store.active == nil)
    #expect(store.completionTick == 1)
}

@MainActor
@Test func skipClearsWithoutCompletion() {
    let store = makeStore(TestClock())
    store.startRest(seconds: 90)
    store.skip()
    #expect(store.active == nil)
    #expect(store.completionTick == 0)
}

@MainActor
@Test func extendAddsFifteen() {
    let clock = TestClock()
    let store = makeStore(clock)
    store.startRest(seconds: 60)
    store.extend()
    #expect(store.active?.endAt == clock.now.addingTimeInterval(75))
}

@MainActor
@Test func newRestReplacesRest() {
    let store = makeStore(TestClock())
    store.startRest(seconds: 60)
    let first = store.active?.id
    store.startRest(seconds: 120)
    #expect(store.active?.id != first)
    #expect(store.active?.seconds == 120)
}

// MARK: - Persistence and notifications

@MainActor
@Test func startPersistsAndRestores() {
    let clock = TestClock()
    let defaults = isolatedDefaults()
    let store = makeStore(clock, defaults: defaults)
    store.startRest(seconds: 90)
    clock.advance(30)
    let restored = makeStore(clock, defaults: defaults)
    #expect(restored.active?.id == store.active?.id)
    #expect(restored.active?.endAt == store.active?.endAt)
}

@MainActor
@Test func completedTimerNotRestored() {
    let clock = TestClock()
    let defaults = isolatedDefaults()
    makeStore(clock, defaults: defaults).startRest(seconds: 90)
    clock.advance(91)
    let restored = makeStore(clock, defaults: defaults)
    #expect(restored.active == nil)
    #expect(restored.completionTick == 0)
    #expect(defaults.data(forKey: TimerStore.storageKey) == nil)
}

@MainActor
@Test func skipRemovesPersisted() {
    let defaults = isolatedDefaults()
    let store = makeStore(TestClock(), defaults: defaults)
    store.startRest(seconds: 90)
    store.skip()
    #expect(defaults.data(forKey: TimerStore.storageKey) == nil)
}

@MainActor
@Test func startSchedulesAfterCancel() async {
    let notifier = FakeTimerNotifier()
    let store = makeStore(TestClock(), notifier: notifier)
    store.startRest(seconds: 90)
    await store.flush()
    #expect(await notifier.cancelCount == 1)
    #expect(await notifier.scheduled == [store.active!.id])
}

@MainActor
@Test func skipCancelsWithoutScheduling() async {
    let notifier = FakeTimerNotifier()
    let store = makeStore(TestClock(), notifier: notifier)
    store.startRest(seconds: 90)
    store.skip()
    await store.flush()
    #expect(await notifier.cancelCount == 2)
    #expect(await notifier.scheduled.count == 1)
}

@MainActor
@Test func extendReschedulesSameId() async {
    let notifier = FakeTimerNotifier()
    let store = makeStore(TestClock(), notifier: notifier)
    store.startRest(seconds: 60)
    let id = store.active!.id
    store.extend()
    await store.flush()
    #expect(await notifier.scheduled == [id, id])
}
