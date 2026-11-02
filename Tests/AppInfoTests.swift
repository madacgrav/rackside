import Foundation
import Testing
@testable import Rackside

@Test func versionWithBuild() {
    #expect(AppInfo.versionString(["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7"]) == "1.0.0 (7)")
}

@Test func versionWithoutBuild() {
    #expect(AppInfo.versionString(["CFBundleShortVersionString": "1.0.0"]) == "1.0.0")
    #expect(AppInfo.versionString(["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": ""]) == "1.0.0")
}

@Test func missingInfo() {
    #expect(AppInfo.versionString(nil) == "—")
}

@Test func aboutLinksAreHTTPSAndDistinct() {
    let links = [AppLinks.guide, AppLinks.privacy, AppLinks.support, AppLinks.changelog, AppLinks.license]
    #expect(links.allSatisfy { $0.scheme == "https" })
    #expect(Set(links).count == links.count)
    #expect(AppLinks.privacy.absoluteString == "https://madacgrav.github.io/trainme/privacy/")
}
