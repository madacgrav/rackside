import Testing
@testable import Rackside

@Test func normalizesTenDigitUSNumbers() {
    #expect(normalizeE164("555-123-4567") == "+15551234567")
    #expect(normalizeE164("(555) 123-4567") == "+15551234567")
    #expect(normalizeE164("5551234567") == "+15551234567")
}

@Test func normalizesElevenDigitUSNumbersWithCountryCode() {
    #expect(normalizeE164("15551234567") == "+15551234567")
    #expect(normalizeE164("1-555-123-4567") == "+15551234567")
}

@Test func preservesInternationalNumbersWithPlus() {
    #expect(normalizeE164("+44 20 7946 0958") == "+442079460958")
    #expect(normalizeE164("+15551234567") == "+15551234567")
}

@Test func rejectsInvalidInput() {
    #expect(normalizeE164("") == nil)
    #expect(normalizeE164("   ") == nil)
    #expect(normalizeE164("123") == nil)
    #expect(normalizeE164("abc") == nil)
    #expect(normalizeE164("555-123-456") == nil)     // 9 digits
    #expect(normalizeE164("+12") == nil)             // too short for E.164
}
