import Foundation
import Testing
@testable import TrainMe

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func timer(_ kind: TimerKind = .rest, seconds: Int = 45, at start: Date = t0) -> ActiveTimer {
    TimerMath.make(kind: kind, seconds: seconds, now: start)
}

private let timedKind = TimerKind.timedSet(plannedEntryId: UUID(), instanceId: UUID())

@Test func remainingNeverNegative() {
    #expect(TimerMath.remaining(timer(), now: t0.addingTimeInterval(100)) == 0)
    #expect(TimerMath.remaining(timer(), now: t0.addingTimeInterval(15)) == 30)
}

@Test func extendFromFutureEndAddsToEnd() {
    let extended = TimerMath.extended(timer(), by: 15, now: t0.addingTimeInterval(10))
    #expect(extended.endAt == t0.addingTimeInterval(60))
}

@Test func extendAfterZeroRestartsFromNow() {
    let later = t0.addingTimeInterval(100)
    #expect(TimerMath.extended(timer(), by: 15, now: later).endAt == later.addingTimeInterval(15))
}

@Test func secondsIncludesExtensions() {
    #expect(TimerMath.extended(timer(), by: 15, now: t0).seconds == 60)
}

@Test func restCannotReplaceRunningTimedSet() {
    #expect(!TimerMath.canReplace(timer(timedKind), with: timer(.rest), now: t0))
}

@Test func timedSetReplacesRest() {
    #expect(TimerMath.canReplace(timer(.rest), with: timer(timedKind), now: t0))
}

@Test func anythingReplacesCompletedTimer() {
    #expect(TimerMath.canReplace(timer(timedKind), with: timer(.rest), now: t0.addingTimeInterval(45)))
}

@Test func sameIdAlwaysReplaces() {
    let running = timer(timedKind)
    var rest = running
    rest.kind = .rest
    #expect(TimerMath.canReplace(running, with: rest, now: t0))
}
