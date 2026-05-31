import Foundation

nonisolated struct SemanticVersion: Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses via the core `parseSemver` FFI — the single source of truth for the
    /// SemVer rules (strip a leading `v`, digits/`.` only, exactly 2–3 parts).
    /// Returns nil on any rejected form (pre-release, build metadata, wrong arity).
    init?(string: String) {
        guard let dto = parseSemver(input: string) else { return nil }
        self.init(major: Int(dto.major), minor: Int(dto.minor), patch: Int(dto.patch))
    }

    var string: String {
        "\(major).\(minor).\(patch)"
    }

    /// Bridges to the FFI DTO so core (`updateAvailable`) can judge this version.
    /// Components are always non-negative in practice (built via the u32-bounded
    /// `init?(string:)`); `clamping` keeps the boundary total without trapping on
    /// same-module misuse, mirroring the checked FFI conversions elsewhere.
    var ffiDto: SemanticVersionDto {
        SemanticVersionDto(
            major: UInt32(clamping: major),
            minor: UInt32(clamping: minor),
            patch: UInt32(clamping: patch)
        )
    }
}
