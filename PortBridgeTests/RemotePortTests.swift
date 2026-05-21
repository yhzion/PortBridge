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

    func test_displayLine_includesPortScopeAndProcessName() {
        let p = RemotePort(port: 8000, address: "0.0.0.0", processName: "vllm")
        XCTAssertEqual(p.displayLine, ":8000 · 모든 인터페이스 · vllm")
    }

    func test_displayLine_omitsMissingProcessName() {
        let p = RemotePort(port: 8000, address: "127.0.0.1", processName: nil)
        XCTAssertEqual(p.displayLine, ":8000 · 로컬 전용")
        XCTAssertFalse(p.displayLine.contains("열린 포트"))
    }
}
