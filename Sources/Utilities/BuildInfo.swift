import Foundation

enum BuildInfo {
    static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    static let buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    static let gitHash: String = Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "dev"
    static let gitBranch: String = Bundle.main.infoDictionary?["GitBranch"] as? String ?? "unknown"
    static let buildDate: String = Bundle.main.infoDictionary?["BuildDate"] as? String ?? "unknown"

    static var displayVersion: String {
        "\(version) (\(buildNumber)) [\(gitHash)]"
    }

    static var fullBuildString: String {
        "\(version) build \(buildNumber) • \(gitHash) on \(gitBranch) • \(buildDate)"
    }
}
