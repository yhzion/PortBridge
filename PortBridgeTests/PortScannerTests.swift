import XCTest
@testable import PortBridge

final class PortScannerTests: XCTestCase {
    func test_ssSuccess_returnsParsedPorts() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*\nLISTEN 0 100 127.0.0.1:5432 0.0.0.0:*",
                stderr: ""
            )
        ]
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(host: "prod")
        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains { $0.port == 3000 })
        XCTAssertTrue(ports.contains { $0.port == 5432 })
    }

    func test_filtersOutOfRangePorts() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:3000 0.0.0.0:*",
                stderr: ""
            )
        ]
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(host: "prod", range: 1000...65535)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
    }

    func test_authFailedStderr_throwsAuthError() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
        ]
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(host: "prod")
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .sshAuthFailed(host: "prod"))
        }
    }
}
