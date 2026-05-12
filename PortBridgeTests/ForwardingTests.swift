import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    private let serverId = UUID()

    func test_idUnique() {
        let a = Forwarding(serverId: serverId, serverDisplayName: "prod", remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(serverId: serverId, serverDisplayName: "prod", remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }

    func test_serverDisplayName_preserved() {
        let fw = Forwarding(serverId: serverId, serverDisplayName: "prod (10.0.0.1)", remotePort: 5432, localPort: 5432, state: .active)
        XCTAssertEqual(fw.serverDisplayName, "prod (10.0.0.1)")
    }
}
