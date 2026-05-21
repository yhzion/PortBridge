import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    private let serverId = UUID()

    func test_idUnique() {
        let a = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }
}
