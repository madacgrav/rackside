import Foundation
import Testing
@testable import Rackside

@MainActor
private func makeStore(_ clock: TestClock, _ sync: FakeWatchSync = FakeWatchSync()) -> TimerStore {
    TimerStore(defaults: isolatedDefaults(), notifier: FakeTimerNotifier(), sync: sync,
               autoComplete: false, now: { clock.now })
}

private let timedKind = TimerKind.timedSet(plannedEntryId: UUID(), instanceId: UUID())

@MainActor
@Test func adoptStartsTimerWithWatchId() {
    let clock = TestClock()
    let store = makeStore(clock)
    let timer = TimerMath.make(kind: .rest, seconds: 60, now: clock.now)
    store.apply(.adopt(timer))
    #expect(store.active == timer)
}

@MainActor
@Test func adoptExtendSameIdReplaces() {
    let clock = TestClock()
    let store = makeStore(clock)
    let timer = TimerMath.make(kind: timedKind, seconds: 45, now: clock.now)
    store.apply(.adopt(timer))
    let extended = TimerMath.extended(timer, by: 15, now: clock.now)
    store.apply(.adopt(extended))
    #expect(store.active?.endAt == extended.endAt)
}

@MainActor
@Test func adoptStaleTimerIgnoredButSnapshotSent() async {
    let clock = TestClock()
    let sync = FakeWatchSync()
    let store = makeStore(clock, sync)
    let stale = TimerMath.make(kind: .rest, seconds: 60, now: clock.now.addingTimeInterval(-120))
    store.apply(.adopt(stale))
    await store.flush()
    #expect(store.active == nil)
    #expect(await sync.sent.count == 1)
}

@MainActor
@Test func adoptRestDuringTimedSetRejectedAndSnapshotSent() async {
    let clock = TestClock()
    let sync = FakeWatchSync()
    let store = makeStore(clock, sync)
    store.startTimedSet(plannedEntryId: UUID(), instanceId: UUID(), seconds: 45)
    let running = store.active
    store.apply(.adopt(TimerMath.make(kind: .rest, seconds: 60, now: clock.now)))
    await store.flush()
    #expect(store.active == running)
    #expect(await sync.sent.last?.timer == running)
}

@MainActor
@Test func skipMatchingIdClears() {
    let store = makeStore(TestClock())
    store.startRest(seconds: 60)
    store.apply(.skip(timerId: store.active!.id))
    #expect(store.active == nil)
}

@MainActor
@Test func skipOtherIdIgnored() {
    let store = makeStore(TestClock())
    store.startRest(seconds: 60)
    store.apply(.skip(timerId: UUID()))
    #expect(store.active != nil)
}

@Test func commandRoundTripsThroughCodec() throws {
    let timer = TimerMath.make(kind: timedKind, seconds: 45, now: Date(timeIntervalSince1970: 1_800_000_000))
    for command in [TimerCommand.adopt(timer), .skip(timerId: timer.id)] {
        let dict = try SyncCodec.encode(command, kind: "command")
        #expect(SyncCodec.decode(TimerCommand.self, from: dict, kind: "command") == command)
    }
}

@MainActor
@Test func setUpNextPushesOnlyOnChange() async {
    let sync = FakeWatchSync()
    let store = makeStore(TestClock(), sync)
    let next = UpNext(plannedEntryId: UUID(), instanceId: UUID(), exerciseName: "Plank", seconds: 45)
    store.setUpNext(next)
    store.setUpNext(next)
    await store.flush()
    #expect(await sync.sent.count == 1)
    #expect(await sync.sent.last?.upNext == next)
}

@MainActor
@Test func listenAppliesStreamedCommands() async {
    let clock = TestClock()
    let sync = FakeWatchSync()
    let store = makeStore(clock, sync)
    let timer = TimerMath.make(kind: .rest, seconds: 60, now: clock.now)
    sync.continuation.yield(.adopt(timer))
    sync.continuation.finish()
    await store.listen()
    #expect(store.active == timer)
}
