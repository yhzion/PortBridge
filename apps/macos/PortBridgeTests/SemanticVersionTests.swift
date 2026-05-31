@testable import PortBridge
import XCTest

final class SemanticVersionTests: XCTestCase {
    func test_parsesWithVPrefix() {
        XCTAssertEqual(
            SemanticVersion(string: "v0.2.0"),
            SemanticVersion(major: 0, minor: 2, patch: 0)
        )
    }

    func test_parsesWithoutVPrefix() {
        XCTAssertEqual(
            SemanticVersion(string: "0.2.0"),
            SemanticVersion(major: 0, minor: 2, patch: 0)
        )
    }

    func test_twoComponent_defaultsPatchToZero() {
        XCTAssertEqual(
            SemanticVersion(string: "0.2"),
            SemanticVersion(major: 0, minor: 2, patch: 0)
        )
    }

    func test_rejectsPreRelease() {
        XCTAssertNil(SemanticVersion(string: "v1.0.0-beta.1"))
        XCTAssertNil(SemanticVersion(string: "1.0.0-rc.2"))
    }

    func test_rejectsGarbage() {
        XCTAssertNil(SemanticVersion(string: "abc"))
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertNil(SemanticVersion(string: "1"))
        XCTAssertNil(SemanticVersion(string: "1.2.3.4"))
    }

    // Version comparison parity now lives in core (`update_available`, exercised
    // through `UpdateChecker.checkNow` in UpdateCheckerTests); Swift's `Comparable`
    // conformance was removed with the hand-rolled parser. The parse cases above
    // are the parity gate for the core-backed `SemanticVersion(string:)`.

    func test_string_roundtrip() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.string, "1.2.3")
    }
}
