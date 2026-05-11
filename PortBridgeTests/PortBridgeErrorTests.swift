import XCTest
@testable import PortBridge

final class PortBridgeErrorTests: XCTestCase {
    func test_localPortInUse_hasDescription() {
        let err = PortBridgeError.localPortInUse(8080)
        XCTAssertTrue(err.errorDescription?.contains("8080") ?? false)
    }

    func test_sshAuthFailed_includesHost() {
        let err = PortBridgeError.sshAuthFailed(host: "prod")
        XCTAssertTrue(err.errorDescription?.contains("prod") ?? false)
    }
}
