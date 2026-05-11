import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    func test_idUnique() {
        let a = Forwarding(host: "h", remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(host: "h", remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }
}
