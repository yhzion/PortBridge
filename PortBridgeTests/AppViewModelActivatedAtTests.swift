@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelActivatedAtTests: XCTestCase {
    func test_forwarding_activatedAt_defaultsToNil() {
        let fw = Forwarding(
            serverId: UUID(),
            remotePort: 80,
            localPort: 80,
            state: .idle
        )
        XCTAssertNil(fw.activatedAt)
    }

    func test_forwarding_activatedAt_canBeAssigned() {
        var fw = Forwarding(
            serverId: UUID(),
            remotePort: 80,
            localPort: 80,
            state: .active
        )
        let now = Date()
        fw.activatedAt = now
        XCTAssertEqual(fw.activatedAt, now)
    }
}
