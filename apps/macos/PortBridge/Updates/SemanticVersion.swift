import Foundation

nonisolated struct SemanticVersion: Comparable, Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(string: String) {
        var s = string
        if s.hasPrefix("v") { s.removeFirst() }
        let allowed: Set<Character> = Set("0123456789.")
        guard !s.isEmpty, s.allSatisfy({ allowed.contains($0) }) else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        let patch: Int
        if parts.count == 3 {
            guard let p = Int(parts[2]) else { return nil }
            patch = p
        } else {
            patch = 0
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    var string: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
