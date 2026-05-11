import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    var hosts: [SSHHost] = []
    var selectedHost: SSHHost?
    var ports: [RemotePort] = []
    var searchText: String = ""
    var forwardings: [Forwarding] = []
    var isScanning: Bool = false
    var lastError: String?
    var pendingPortConflict: PortConflict?

    private let parser: () throws -> [SSHHost]
    private let scanner: PortScanner
    private let tunnels: TunnelManager

    init(
        parser: @escaping () throws -> [SSHHost] = { try SSHConfigParser.parse() },
        scanner: PortScanner = PortScanner(runner: ProcessCommandRunner()),
        tunnels: TunnelManager? = nil
    ) {
        self.parser = parser
        self.scanner = scanner
        self.tunnels = tunnels ?? TunnelManager()
        self.tunnels.delegate = self
    }

    var filteredPorts: [RemotePort] {
        guard !searchText.isEmpty else { return ports }
        let q = searchText.lowercased()
        return ports.filter {
            String($0.port).contains(q) ||
            ($0.processName?.lowercased().contains(q) ?? false)
        }
    }

    func loadHosts() {
        do {
            hosts = try parser()
        } catch let error as PortBridgeError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scan() async {
        guard let host = selectedHost else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            ports = try await scanner.scan(host: host.name)
        } catch let error as PortBridgeError {
            lastError = error.errorDescription
            ports = []
        } catch {
            lastError = error.localizedDescription
            ports = []
        }
    }

    func toggleForwarding(for port: RemotePort) async {
        guard let host = selectedHost else { return }
        if let existing = forwardings.first(where: { $0.host == host.name && $0.remotePort == port.port }) {
            tunnels.stop(existing.id)
            forwardings.removeAll { $0.id == existing.id }
            return
        }
        await startForwarding(host: host.name, remotePort: port.port, localPort: port.port)
    }

    func resolveConflict(with newLocalPort: Int) async {
        guard let pending = pendingPortConflict else { return }
        pendingPortConflict = nil
        await startForwarding(host: pending.host, remotePort: pending.remotePort, localPort: newLocalPort)
    }

    func shutdownAll() {
        tunnels.shutdownAll()
        forwardings.removeAll()
    }

    private func startForwarding(host: String, remotePort: Int, localPort: Int) async {
        let placeholderID = UUID()
        let placeholder = Forwarding(
            id: placeholderID,
            host: host,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting
        )
        forwardings.append(placeholder)

        do {
            let fw = try await tunnels.start(host: host, remotePort: remotePort, localPort: localPort)
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
            } else {
                forwardings.append(fw)
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr) where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            pendingPortConflict = PortConflict(host: host, remotePort: remotePort, attemptedLocal: localPort)
        } catch let error as PortBridgeError {
            forwardings.removeAll { $0.id == placeholderID }
            lastError = error.errorDescription
        } catch {
            forwardings.removeAll { $0.id == placeholderID }
            lastError = error.localizedDescription
        }
    }
}

struct PortConflict: Identifiable, Equatable {
    let id = UUID()
    let host: String
    let remotePort: Int
    let attemptedLocal: Int
}

extension AppViewModel: TunnelManagerDelegate {
    nonisolated func tunnelDidExit(id: UUID, stderr: String) async {
        await MainActor.run {
            if let idx = forwardings.firstIndex(where: { $0.id == id }) {
                forwardings[idx].state = .error(stderr)
            }
        }
    }
}
