import EventKit
import Testing
@testable import Rackside

@Test func calendarErrorIsEquatable() {
    #expect(CalendarError.noWritableCalendar == .noWritableCalendar)
}

@Test func fakeCalendarReportsConfiguredStatus() async {
    let calendar = FakeCalendar()
    #expect(await calendar.authorizationStatus() == .fullAccess)
    await calendar.configure(status: .denied)
    #expect(await calendar.authorizationStatus() == .denied)
    #expect(await calendar.requestAccess() == false)
}
