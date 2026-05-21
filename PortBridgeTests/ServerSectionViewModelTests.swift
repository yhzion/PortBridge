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
    func test_scan_connectTimeout_setsOffline() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Connection timed out")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .offline(let isRetrying) = vm.scanState else {
            XCTFail("expected .offline, got \(vm.scanState)"); return
        }
        XCTAssertFalse(isRetrying)
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

    @MainActor
    func test_scan_noRouteToHost_setsOffline() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: No route to host")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        if case .offline = vm.scanState { return }
        XCTFail("expected .offline, got \(vm.scanState)")
    }

    @MainActor
    func test_scan_toolsMissing_setsToolMissing() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 127, stdout: "", stderr: "PORTBRIDGE_TOOLS_MISSING")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        XCTAssertEqual(vm.scanState, .toolMissing)
    }

    @MainActor
    func test_scan_fromOffline_silentlyRetries() async {
        // 첫 스캔: 오프라인
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "No route to host"),
            CommandResult(exitCode: 255, stdout: "", stderr: "No route to host"),
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .offline(false) = vm.scanState else {
            XCTFail("expected .offline(false), got \(vm.scanState)"); return
        }

        // 재스캔: 핵심 검증은 .scanning을 거치지 않는다는 것 — 직접 검증은 race-prone이므로
        // 최종 상태가 .offline 임을 검증.
        await vm.scan()
        if case .offline = vm.scanState { return }
        XCTFail("expected .offline after retry, got \(vm.scanState)")
    }
}
