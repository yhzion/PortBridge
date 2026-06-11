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

    func test_serverUnreachable_exposesSummarizedReason() {
        let err = PortBridgeError.serverUnreachable(host: "prod-api", reason: "No route to host")
        XCTAssertTrue(err.errorDescription?.contains("네트워크 경로") ?? false)
    }

    func test_forwardingDiedEarly_summarizesStderr() {
        let err = PortBridgeError.forwardingDiedEarly(stderr: "bind: Address already in use")
        XCTAssertTrue(err.errorDescription?.contains("이미 사용 중") ?? false)
    }

    func test_remoteToolsMissing_hasDescription() {
        let err = PortBridgeError.remoteToolsMissing
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }
}
