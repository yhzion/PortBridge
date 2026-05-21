import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    private let serverId = UUID()

    func test_idUnique() {
        let a = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_errorState_equatableByAssociatedValue() {
        XCTAssertEqual(Forwarding.State.error("a"), Forwarding.State.error("a"))
        XCTAssertNotEqual(Forwarding.State.error("a"), Forwarding.State.error("b"))
    }
}
