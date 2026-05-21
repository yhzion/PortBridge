@testable import PortBridge
import XCTest

final class ScanOutputParserTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: "txt") {
            return url
        }
        fatalError("Fixture \(name).txt not found")
    }

    private func fixture(_ name: String) -> String {
        try! String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    // MARK: - parseSS

    func test_parseSS_noHeader_threePorts() {
        let ports = ScanOutputParser.parseSS(fixture("ss_no_header"))
        XCTAssertEqual(ports.count, 4)
        XCTAssertTrue(ports.contains { $0.port == 22 && $0.address == "0.0.0.0" })
        XCTAssertTrue(ports.contains { $0.port == 5432 && $0.address == "127.0.0.1" })
        XCTAssertTrue(ports.contains { $0.port == 80 && $0.address == "::" })
    }

    func test_parseSS_withHeader_skipsHeaderLine() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv4_only"))
        XCTAssertEqual(ports.count, 2)
    }

    func test_parseSS_ipv6Mixed_handlesBrackets() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv6_mixed"))
        XCTAssertEqual(ports.count, 3)
        XCTAssertTrue(ports.contains { $0.port == 22 && $0.address == "::" })
        XCTAssertTrue(ports.contains { $0.port == 5432 && $0.address == "::1" })
    }

    func test_parseSS_extractsProcessName() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv6_mixed"))
        let p22 = ports.first { $0.port == 22 }
        XCTAssertEqual(p22?.processName, "sshd")
    }

    // MARK: - parseLsof

    func test_parseLsof_typical_threePorts() {
        let ports = ScanOutputParser.parseLsof(fixture("lsof_typical"))
        XCTAssertEqual(ports.count, 3)
        XCTAssertTrue(ports.contains { $0.port == 22 && $0.processName == "sshd" })
        XCTAssertTrue(ports.contains { $0.port == 5432 && $0.processName == "postgres" })
    }

    func test_parseLsof_noProcess_treatsDashAsNil() {
        let ports = ScanOutputParser.parseLsof(fixture("lsof_no_process"))
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
        XCTAssertNil(ports.first?.processName)
    }
}
