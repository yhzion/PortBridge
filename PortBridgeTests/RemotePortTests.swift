import XCTest
@testable import PortBridge

final class RemotePortTests: XCTestCase {
    func test_id_combinesAddressAndPort() {
        let p = RemotePort(port: 5432, address: "0.0.0.0", processName: "postgres")
        XCTAssertEqual(p.id, "0.0.0.0:5432")
    }

    func test_processNameOptional() {
        let p = RemotePort(port: 8080, address: "127.0.0.1", processName: nil)
        XCTAssertNil(p.processName)
    }
}
