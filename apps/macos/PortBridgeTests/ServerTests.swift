@testable import PortBridge
import XCTest

final class ServerTests: XCTestCase {
    func test_displayName_withName_showsNameAndHost() {
        let s = Server(name: "prod", user: "ubuntu", host: "10.0.0.1")
        XCTAssertEqual(s.displayName, "prod (10.0.0.1)")
    }

    func test_displayName_withoutName_showsHostOnly() {
        let s = Server(name: nil, user: "ubuntu", host: "10.0.0.1")
        XCTAssertEqual(s.displayName, "10.0.0.1")
    }

    func test_sshTarget_combinesUserAndHost() {
        let s = Server(user: "deploy", host: "192.168.1.5")
        XCTAssertEqual(s.sshTarget, "deploy@192.168.1.5")
    }

    func test_defaultPort_is22() {
        let s = Server(user: "u", host: "h")
        XCTAssertEqual(s.port, 22)
    }

    func test_codable_roundtrip() throws {
        let s = Server(name: "test", user: "u", host: "h", port: 2222)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        XCTAssertEqual(s, decoded)
    }
}
