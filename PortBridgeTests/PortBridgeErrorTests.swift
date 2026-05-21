import XCTest
@testable import PortBridge

final class PortBridgeErrorTests: XCTestCase {
    func test_sshAuthFailed_includesHost() {
        let err = PortBridgeError.sshAuthFailed(host: "prod")
        XCTAssertTrue(err.errorDescription?.contains("prod") ?? false)
    }
}
