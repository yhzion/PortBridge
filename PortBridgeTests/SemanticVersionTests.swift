@testable import PortBridge
import XCTest

final class SemanticVersionTests: XCTestCase {
    func test_parsesWithVPrefix() {
        XCTAssertEqual(SemanticVersion(string: "v0.2.0"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    func test_parsesWithoutVPrefix() {
        XCTAssertEqual(SemanticVersion(string: "0.2.0"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    func test_twoComponent_defaultsPatchToZero() {
        XCTAssertEqual(SemanticVersion(string: "0.2"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
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

    func test_comparison_basic() {
        XCTAssertTrue(SemanticVersion(string: "0.2.0")! > SemanticVersion(string: "0.1.9")!)
    }

    func test_comparison_avoidsLexicographicTrap() {
        XCTAssertTrue(SemanticVersion(string: "0.10.0")! > SemanticVersion(string: "0.9.0")!)
    }

    func test_comparison_majorDominates() {
        XCTAssertTrue(SemanticVersion(string: "1.0.0")! > SemanticVersion(string: "0.99.99")!)
    }

    func test_string_roundtrip() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.string, "1.2.3")
    }
}
