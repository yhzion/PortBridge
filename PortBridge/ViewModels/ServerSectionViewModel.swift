// PortBridge/ViewModels/ServerSectionViewModel.swift
import Foundation
import Observation

enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case error(String)
    case authFailed(copyCommand: String)
}

@MainActor
@Observable
final class ServerSectionViewModel: Identifiable {
    private(set) var server: Server
    private(set) var scanState: ServerScanState = .idle
    private(set) var isExpanded: Bool = true

    private let scanner: PortScanner

    var id: UUID { server.id }

    init(server: Server, scanner: PortScanner = PortScanner(runner: ProcessCommandRunner())) {
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
        guard scanState != .scanning else { return }
        scanState = .scanning
        do {
            let loaded = try await scanner.scan(server: server)
            scanState = .loaded(loaded)
        } catch PortBridgeError.sshAuthFailed {
            scanState = .authFailed(copyCommand: "ssh-copy-id \(server.sshTarget)")
        } catch let error as PortBridgeError {
            scanState = .error(error.errorDescription ?? error.localizedDescription)
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }
}
