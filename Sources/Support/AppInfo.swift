import Foundation

/// Version text shown in Settings › About.
enum AppInfo {
    /// "1.0.0 (1)"; tolerates a missing build or dictionary (tests, previews).
    static func versionString(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

/// Public pages on the GitHub Pages docs site (docs/).
enum AppLinks {
    private static let base = URL(string: "https://madacgrav.github.io/trainme/")!
    static let guide = base.appending(path: "guide/")
    static let privacy = base.appending(path: "privacy/")
    static let support = base.appending(path: "support/")
    static let changelog = base.appending(path: "changelog/")
    static let license = URL(string: "https://github.com/madacgrav/trainme/blob/main/LICENSE")!
}
