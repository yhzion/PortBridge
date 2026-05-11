import XCTest
@testable import PortBridge

final class SSHHostTests: XCTestCase {
    func test_id_equalsName() {
        let host = SSHHost(name: "prod", hostName: "10.0.0.1", user: "ubuntu", port: 22)
        XCTAssertEqual(host.id, "prod")
    }

    func test_minimalHost_hasOptionalFieldsAsNil() {
        let host = SSHHost(name: "bare")
        XCTAssertEqual(host.name, "bare")
        XCTAssertNil(host.hostName)
        XCTAssertNil(host.user)
        XCTAssertNil(host.port)
    }
}
