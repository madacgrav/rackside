import Foundation
import Testing
@testable import Rackside

/// The app's Info.plist must resolve the version build settings, not keep literals.
@Test func bundleVersionIsSemanticAndResolved() {
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? ""
    #expect(short.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
    let build = info["CFBundleVersion"] as? String ?? "$"
    #expect(!build.isEmpty && !build.contains("$"))
}
