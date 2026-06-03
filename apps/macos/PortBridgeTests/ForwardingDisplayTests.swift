@testable import PortBridge
import XCTest

final class ForwardingDisplayTests: XCTestCase {
    // MARK: - suffix / line

    func test_active_suffix_includesArrowAndProcess() {
        let d = ForwardingDisplay.active(host: "myserver (1.2.3.4)", remotePort: 8080, localPort: 3000, processName: "nginx")
        XCTAssertEqual(d.suffix, ":8080 → :3000 · nginx")
        XCTAssertEqual(d.line, "myserver (1.2.3.4):8080 → :3000 · nginx")
    }

    func test_active_suffix_omitsProcessWhenNil() {
        let d = ForwardingDisplay.active(host: "h", remotePort: 8080, localPort: 3000, processName: nil)
        XCTAssertEqual(d.suffix, ":8080 → :3000")
    }

    func test_inactive_suffix_noArrow() {
        let d = ForwardingDisplay.inactive(host: "h", remotePort: 5432, processName: "postgres")
        XCTAssertEqual(d.suffix, ":5432 · postgres")
        XCTAssertEqual(d.line, "h:5432 · postgres")
    }

    func test_starting_suffix_noArrow() {
        let d = ForwardingDisplay.starting(host: "h", remotePort: 5432, processName: nil)
        XCTAssertEqual(d.suffix, ":5432")
    }

    func test_error_suffix_noArrow_keepsMessage() {
        let d = ForwardingDisplay.error(host: "h", remotePort: 3389, message: "connection refused", processName: "rdp")
        XCTAssertEqual(d.suffix, ":3389 · rdp")
        XCTAssertEqual(d.errorMessage, "connection refused")
    }

    // MARK: - statusDot

    func test_statusDot_activeAndStarting_filled() {
        XCTAssertEqual(ForwardingDisplay.active(host: "h", remotePort: 1, localPort: 1, processName: nil).statusDot, "●")
        XCTAssertEqual(ForwardingDisplay.starting(host: "h", remotePort: 1, processName: nil).statusDot, "●")
    }

    func test_statusDot_errorAndInactive_hollow() {
        XCTAssertEqual(ForwardingDisplay.error(host: "h", remotePort: 1, message: "x", processName: nil).statusDot, "○")
        XCTAssertEqual(ForwardingDisplay.inactive(host: "h", remotePort: 1, processName: nil).statusDot, "○")
    }

    // MARK: - invariants (factory가 타입으로 강제)

    func test_nonActiveFactories_haveNilLocalPort() {
        XCTAssertNil(ForwardingDisplay.inactive(host: "h", remotePort: 1, processName: nil).localPort)
        XCTAssertNil(ForwardingDisplay.starting(host: "h", remotePort: 1, processName: nil).localPort)
        XCTAssertNil(ForwardingDisplay.error(host: "h", remotePort: 1, message: "x", processName: nil).localPort)
    }

    func test_errorMessage_onlyOnError() {
        XCTAssertNil(ForwardingDisplay.active(host: "h", remotePort: 1, localPort: 1, processName: nil).errorMessage)
        XCTAssertNil(ForwardingDisplay.inactive(host: "h", remotePort: 1, processName: nil).errorMessage)
        XCTAssertEqual(ForwardingDisplay.error(host: "h", remotePort: 1, message: "boom", processName: nil).errorMessage, "boom")
    }

    // MARK: - host는 verbatim (name→host 매핑은 Server.displayName 소관, §3.1)

    func test_host_usedVerbatim() {
        XCTAssertEqual(ForwardingDisplay.inactive(host: "1.2.3.4", remotePort: 1, processName: nil).line, "1.2.3.4:1")
        XCTAssertEqual(ForwardingDisplay.inactive(host: "myserver (1.2.3.4)", remotePort: 1, processName: nil).line, "myserver (1.2.3.4):1")
    }
}
