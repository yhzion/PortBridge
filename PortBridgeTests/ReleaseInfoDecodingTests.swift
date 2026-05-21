@testable import PortBridge
import XCTest

final class ReleaseInfoDecodingTests: XCTestCase {
    func test_decodesGitHubFixture() throws {
        let url = Bundle(for: type(of: self))
            .url(forResource: "github-release-latest", withExtension: "json")
        XCTAssertNotNil(url, "Fixture not bundled — check Copy Bundle Resources")

        let data = try Data(contentsOf: XCTUnwrap(url))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let info = try decoder.decode(ReleaseInfo.self, from: data)
        XCTAssertEqual(info.tagName, "v0.2.0")
        XCTAssertEqual(
            info.htmlURL.absoluteString,
            "https://github.com/yhzion/PortBridge/releases/tag/v0.2.0"
        )
        XCTAssertEqual(info.name, "v0.2.0")
        XCTAssertNotNil(info.publishedAt)
        XCTAssertEqual(info.version, SemanticVersion(major: 0, minor: 2, patch: 0))
    }
}
