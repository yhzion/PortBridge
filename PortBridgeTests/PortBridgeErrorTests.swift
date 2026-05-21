@testable import PortBridge
import XCTest

final class PortBridgeErrorTests: XCTestCase {
    func test_sshAuthFailed_includesHost() {
        let err = PortBridgeError.sshAuthFailed(host: "prod")
        XCTAssertTrue(err.errorDescription?.contains("prod") ?? false)
    }

    func test_serverUnreachable_includesHost() {
        let err = PortBridgeError.serverUnreachable(host: "prod-api", reason: "no route to host")
        XCTAssertTrue(err.errorDescription?.contains("prod-api") ?? false)
    }

    func test_remoteToolsMissing_hasDescription() {
        let err = PortBridgeError.remoteToolsMissing
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }
}
