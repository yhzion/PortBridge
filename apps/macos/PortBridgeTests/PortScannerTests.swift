// PortBridgeTests/PortScannerTests.swift
@testable import PortBridge
import XCTest

final class PortScannerTests: XCTestCase {
    private func makeServer(user: String = "ubuntu", host: String = "prod", port: Int = 22) -> Server {
        Server(user: user, host: host, port: port)
    }

    func test_ssSuccess_returnsParsedPorts() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*\nLISTEN 0 100 127.0.0.1:5432 0.0.0.0:*",
                stderr: ""
            )
        ])
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(server: makeServer())
        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains { $0.port == 3000 })
        XCTAssertTrue(ports.contains { $0.port == 5432 })
    }

    func test_filtersOutOfRangePorts() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:3000 0.0.0.0:*",
                stderr: ""
            )
        ])
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(server: makeServer(), range: 1000 ... 65535)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
    }

    func test_scan_deduplicatesIPv4AndIPv6WildcardForSamePort() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(
                exitCode: 0,
                stdout: """
                LISTEN 0 4096 0.0.0.0:8000 0.0.0.0:* users:(("vllm",pid=1,fd=3))
                LISTEN 0 4096 [::]:8000 [::]:* users:(("vllm",pid=1,fd=4))
                """,
                stderr: ""
            )
        ])
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(server: makeServer())
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 8000)
        XCTAssertEqual(ports.first?.address, "0.0.0.0")
        XCTAssertEqual(ports.first?.processName, "vllm")
    }

    func test_scan_deduplicatesLoopbackForSamePort() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(
                exitCode: 0,
                stdout: """
                LISTEN 0 4096 127.0.0.1:8000 0.0.0.0:*
                LISTEN 0 4096 [::1]:8000 [::]:*
                """,
                stderr: ""
            )
        ])
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(server: makeServer())
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.address, "127.0.0.1")
    }

    func test_authFailedStderr_throwsAuthError() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .sshAuthFailed(host: "prod"))
        }
    }

    func test_connectionTimedOut_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Connection timed out")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable(let host, _) = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
            XCTAssertEqual(host, "prod")
        }
    }

    func test_noRouteToHost_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host 10.0.0.1 port 22: No route to host")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }

    func test_connectionRefused_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Connection refused")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }

    func test_couldNotResolveHostname_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: Could not resolve hostname prod: Name or service not known")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }

    func test_networkUnreachable_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Network is unreachable")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }

    func test_hostIsDown_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Host is down")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }

    func test_sshArgs_includePortAndTarget() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([CommandResult(exitCode: 0, stdout: "", stderr: "")])
        let scanner = PortScanner(runner: mock)
        let server = Server(user: "deploy", host: "10.0.0.1", port: 2222)
        _ = try await scanner.scan(server: server)
        let args = await mock.calls.first?.args ?? []
        XCTAssertTrue(args.contains("-p"), "args should contain -p flag")
        XCTAssertTrue(args.contains("2222"), "args should contain port")
        XCTAssertTrue(args.contains("deploy@10.0.0.1"), "args should contain user@host")
    }

    func test_toolsMissingMarker_throwsRemoteToolsMissing() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 127, stdout: "", stderr: "PORTBRIDGE_TOOLS_MISSING\n")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .remoteToolsMissing)
        }
    }

    func test_exit127WithoutMarker_throwsRemoteToolsMissing() async throws {
        // 일부 셸은 stderr 출력 없이 127만 반환 — fallback으로도 잡혀야 함.
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 127, stdout: "", stderr: "")
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .remoteToolsMissing)
        }
    }

    func test_emptyStdoutWithoutErrorSignal_returnsEmptyArray() async throws {
        // 도구 부재가 아니라 단순히 listening 포트가 없는 경우 — 빈 배열 반환.
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(server: makeServer())
        XCTAssertEqual(ports.count, 0)
    }

    /// macOS BSD 소켓은 도달 불가 호스트에 대해 "Operation timed out"을 출력함
    /// (Linux는 "Connection timed out"). 두 표기 모두 .serverUnreachable로 분류되어야 함.
    func test_operationTimedOut_throwsServerUnreachable() async throws {
        let mock = MockCommandRunner()
        await mock.setResponses([
            CommandResult(
                exitCode: 255,
                stdout: "",
                stderr: "ssh: connect to host 10.99.99.99 port 22: Operation timed out\n"
            )
        ])
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            guard case .serverUnreachable = error else {
                XCTFail("expected .serverUnreachable, got \(error)"); return
            }
        }
    }
}
