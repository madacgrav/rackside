import Testing
@testable import Rackside

private struct Boom: Error {}

@Test func newEventStoresIdentifier() {
    #expect(resolveEventIdentifier(existing: nil, wantsCalendar: true, hasAccess: true, result: .success("e1")) == .store("e1"))
}

@Test func sameIdentifierIsUnchanged() {
    #expect(resolveEventIdentifier(existing: "e1", wantsCalendar: true, hasAccess: true, result: .success("e1")) == .unchanged)
}

@Test func failedUpdateKeepsExistingIdentifier() {
    let outcome = resolveEventIdentifier(existing: "e1", wantsCalendar: true, hasAccess: true, result: .failure(Boom()))
    guard case .failed = outcome else {
        Issue.record("expected .failed, got \(outcome)")
        return
    }
}

@Test func noWritableCalendarHasSpecificMessage() {
    let outcome = resolveEventIdentifier(
        existing: nil, wantsCalendar: true, hasAccess: true,
        result: .failure(CalendarError.noWritableCalendar)
    )
    #expect(outcome == .failed("Saved, but there is no writable calendar on this phone."))
}

@Test func toggleOffRemoveSuccessClears() {
    #expect(resolveEventIdentifier(existing: "e1", wantsCalendar: false, hasAccess: false, result: .success(nil)) == .store(nil))
}

@Test func toggleOffRemoveFailureKeepsIdentifier() {
    let outcome = resolveEventIdentifier(existing: "e1", wantsCalendar: false, hasAccess: false, result: .failure(Boom()))
    guard case .failed = outcome else {
        Issue.record("expected .failed, got \(outcome)")
        return
    }
}

@Test func toggleOffNothingToRemoveIsUnchanged() {
    #expect(resolveEventIdentifier(existing: nil, wantsCalendar: false, hasAccess: false, result: nil) == .unchanged)
}

@Test func deniedAccessWarnsOnlyForNewEvents() {
    let fresh = resolveEventIdentifier(existing: nil, wantsCalendar: true, hasAccess: false, result: nil)
    guard case .failed = fresh else {
        Issue.record("expected .failed, got \(fresh)")
        return
    }
    #expect(resolveEventIdentifier(existing: "e1", wantsCalendar: true, hasAccess: false, result: nil) == .unchanged)
}

@Test func capturingWrapsSuccessAndFailure() async {
    let ok = await capturing { "x" }
    #expect((try? ok.get()) == "x")
    let bad: Result<String, any Error> = await capturing { throw Boom() }
    #expect((try? bad.get()) == nil)
}
