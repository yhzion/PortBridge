// PortBridgeTests/PortScannerTests.swift
import XCTest
@testable import PortBridge

final class PortScannerTests: XCTestCase {
    private func makeServer(user: String = "ubuntu", host: String = "prod", port: Int = 22) -> Server {
        Server(user: user, host: host, port: port)
    }

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
        let ports = try await scanner.scan(server: makeServer())
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
        let ports = try await scanner.scan(server: makeServer(), range: 1000...65535)
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
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .sshAuthFailed(host: "prod"))
        }
    }

    func test_sshArgs_includePortAndTarget() async throws {
        let mock = MockCommandRunner()
        mock.responses = [CommandResult(exitCode: 0, stdout: "", stderr: "")]
        let scanner = PortScanner(runner: mock)
        let server = Server(user: "deploy", host: "10.0.0.1", port: 2222)
        _ = try await scanner.scan(server: server)
        let args = mock.calls.first?.args ?? []
        XCTAssertTrue(args.contains("-p"), "args should contain -p flag")
        XCTAssertTrue(args.contains("2222"), "args should contain port")
        XCTAssertTrue(args.contains("deploy@10.0.0.1"), "args should contain user@host")
    }
}
