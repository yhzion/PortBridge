import XCTest
@testable import PortBridge

final class SSHConfigParserTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: type(of: self))
        // Try with subdirectory first
        if let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") {
            return url
        }
        // Fallback: flat lookup (Xcode 16 synchronized folders may flatten)
        if let url = bundle.url(forResource: name, withExtension: "txt") {
            return url
        }
        fatalError("Fixture \(name).txt not found in test bundle")
    }

    func test_basic_parsesTwoHostsWithOptions() throws {
        let hosts = try SSHConfigParser.parse(path: fixtureURL("config_basic"))
        XCTAssertEqual(hosts.count, 2)

        let prod = hosts.first { $0.name == "prod" }
        XCTAssertEqual(prod?.hostName, "10.0.0.1")
        XCTAssertEqual(prod?.user, "ubuntu")
        XCTAssertEqual(prod?.port, 2222)

        let staging = hosts.first { $0.name == "staging" }
        XCTAssertEqual(staging?.hostName, "10.0.0.2")
        XCTAssertEqual(staging?.user, "deploy")
        XCTAssertNil(staging?.port)
    }
}
