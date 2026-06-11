// PortBridge/ViewModels/ServerSectionViewModel.swift
import Foundation
import Observation

enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case offline(isRetrying: Bool)
    case toolMissing
    case error(String)
    case authFailed(copyCommand: String)
    case hostKeyFailed(copyCommand: String)
}

@MainActor
@Observable
final class ServerSectionViewModel: Identifiable {
    private(set) var server: Server
    private(set) var scanState: ServerScanState = .idle
    private(set) var isExpanded: Bool = true

    private let scanner: PortScanner

    var id: UUID {
        server.id
    }

    init(server: Server, scanner: PortScanner = PortScanner(runner: BlockingProcessRunner())) {
        self.server = server
        self.scanner = scanner
    }

    func update(server: Server) {
        self.server = server
    }

    var ports: [RemotePort] {
        if case .loaded(let ports) = scanState { return ports }
        return []
    }

    func scan() async {
        if case .scanning = scanState { return }
        if case .offline(true) = scanState { return } // 이미 silent retry 중

        let wasOffline = if case .offline = scanState { true } else { false }

        scanState = wasOffline ? .offline(isRetrying: true) : .scanning

        do {
            let loaded = try await scanner.scan(server: server)
            scanState = .loaded(loaded)
        } catch PortBridgeError.sshAuthFailed {
            scanState = .authFailed(copyCommand: "ssh-copy-id \(server.sshTarget)")
        } catch PortBridgeError.serverUnreachable(_, let reason)
            where SSHErrorSummarizer.isHostKeyFailure(reason) {
            // 보안 관련 실패 — 무해한 오프라인으로 위장하면 사용자가
            // StrictHostKeyChecking 비활성화 같은 위험한 우회로 빠진다.
            scanState = .hostKeyFailed(
                copyCommand: Self.hostKeyResetCommand(host: server.host, port: server.port)
            )
        } catch PortBridgeError.serverUnreachable {
            scanState = .offline(isRetrying: false)
        } catch PortBridgeError.remoteToolsMissing {
            scanState = .toolMissing
        } catch let error as PortBridgeError {
            scanState = .error(error.errorDescription ?? error.localizedDescription)
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    /// known_hosts에서 기존 키를 제거하는 명령. 비표준 포트는 `[host]:port` 항목으로 저장되므로
    /// 형식을 맞춰야 한다. 순수 함수로 분리해 테스트 대상으로 노출.
    static func hostKeyResetCommand(host: String, port: Int) -> String {
        port == 22 ? "ssh-keygen -R \(host)" : "ssh-keygen -R '[\(host)]:\(port)'"
    }
}

#if DEBUG
    extension ServerSectionViewModel {
        // Test-only helper to inject a scan state without driving an async scan.
        // swiftlint:disable:next identifier_name
        func _test_setScanState(_ state: ServerScanState) {
            scanState = state
        }
    }
#endif
