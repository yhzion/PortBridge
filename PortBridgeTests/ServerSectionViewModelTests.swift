// PortBridgeTests/ServerSectionViewModelTests.swift
import XCTest
@testable import PortBridge

final class ServerSectionViewModelTests: XCTestCase {
    private func makeServer() -> Server {
        Server(user: "ubuntu", host: "10.0.0.1")
    }

    @MainActor
    func test_initialState_isIdle() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertEqual(vm.scanState, .idle)
    }

    @MainActor
    func test_scan_success_setsLoaded() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 0, stdout: "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*", stderr: "")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .loaded(let ports) = vm.scanState else {
            XCTFail("expected .loaded, got \(vm.scanState)"); return
        }
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
    }

    @MainActor
    func test_scan_authFailed_setsAuthFailed() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .authFailed(let cmd) = vm.scanState else {
            XCTFail("expected .authFailed, got \(vm.scanState)"); return
        }
        XCTAssertTrue(cmd.contains("ssh-copy-id"))
        XCTAssertTrue(cmd.contains("ubuntu@10.0.0.1"))
    }

    @MainActor
    func test_scan_connectTimeout_setsError() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Connection timed out")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .error = vm.scanState else {
            XCTFail("expected .error, got \(vm.scanState)"); return
        }
    }

    @MainActor
    func test_ports_whenLoaded_returnsPorts() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 0, stdout: "LISTEN 0 128 0.0.0.0:8080 0.0.0.0:*", stderr: "")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        XCTAssertEqual(vm.ports.count, 1)
        XCTAssertEqual(vm.ports.first?.port, 8080)
    }

    @MainActor
    func test_ports_whenIdle_isEmpty() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertTrue(vm.ports.isEmpty)
    }

    @MainActor
    func test_toggleExpanded_flipsValue() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertTrue(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertFalse(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertTrue(vm.isExpanded)
    }

    @MainActor
    func test_id_equalsServerId() {
        let server = makeServer()
        let vm = ServerSectionViewModel(server: server)
        XCTAssertEqual(vm.id, server.id)
    }
}
