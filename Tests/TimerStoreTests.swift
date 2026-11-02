import Foundation
import Testing
@testable import TrainMe

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func makeStore(_ clock: TestClock) -> TimerStore {
    TimerStore(autoComplete: false, now: { clock.now })
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
