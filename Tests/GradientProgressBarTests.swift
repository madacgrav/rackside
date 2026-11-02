import Foundation
import Testing
@testable import Rackside

@Test @MainActor func remainingFractionCountsDown() {
    let start = Date(timeIntervalSince1970: 0)
    let interval = start...start.addingTimeInterval(100)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start) == 1)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start.addingTimeInterval(25)) == 0.75)
    #expect(GradientProgressBar.remainingFraction(of: interval, at: start.addingTimeInterval(200)) == 0)
    #expect(GradientProgressBar.remainingFraction(of: start...start, at: start) == 0)
}
