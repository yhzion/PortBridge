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

    func test_wildcardHosts_excluded() throws {
        let hosts = try SSHConfigParser.parse(path: fixtureURL("config_wildcard"))
        XCTAssertFalse(hosts.contains { $0.name == "*" })
        XCTAssertFalse(hosts.contains { $0.name == "!blocked" })
    }

    func test_multipleHostsOnOneLine_eachRegistered() throws {
        let hosts = try SSHConfigParser.parse(path: fixtureURL("config_wildcard"))
        let names = hosts.map(\.name)
        XCTAssertTrue(names.contains("db1"))
        XCTAssertTrue(names.contains("db2"))
        XCTAssertTrue(names.contains("db3"))
        let dbs = hosts.filter { $0.name.hasPrefix("db") }
        XCTAssertTrue(dbs.allSatisfy { $0.user == "postgres" })
    }

    func test_include_recursivelyLoadsSubFile() throws {
        let hosts = try SSHConfigParser.parse(path: fixtureURL("config_include"))
        let names = hosts.map(\.name)
        XCTAssertTrue(names.contains("main"))
        XCTAssertTrue(names.contains("included"))
        let included = hosts.first { $0.name == "included" }
        XCTAssertEqual(included?.user, "extra")
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
