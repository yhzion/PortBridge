import Foundation

extension Bundle {
    /// Reads `CFBundleShortVersionString` and parses it as SemanticVersion.
    /// Returns nil if the key is missing or the value is not a valid SemVer triple.
    var currentVersion: SemanticVersion? {
        guard let s = infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return SemanticVersion(string: s)
    }
}
