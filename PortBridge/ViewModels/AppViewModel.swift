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
    private(set) var activatedAt: [UUID: Date] = [:]

    #if DEBUG
    func setActivatedAtForTesting(_ id: UUID, _ date: Date) {
        activatedAt[id] = date
    }
    #endif

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

    var activeForwardedPorts: [(port: RemotePort, forwarding: Forwarding)] {
        let active = forwardings.filter { fw in
            guard fw.host == selectedHost?.name else { return false }
            switch fw.state {
            case .active, .starting, .error: return true
            case .idle: return false
            }
        }
        return active
            .compactMap { fw in
                ports.first(where: { $0.port == fw.remotePort }).map { (port: $0, forwarding: fw) }
            }
            .sorted {
                activatedAt[$0.forwarding.id, default: .distantPast]
                > activatedAt[$1.forwarding.id, default: .distantPast]
            }
    }

    var inactivePorts: [RemotePort] {
        let activePortNums = Set(activeForwardedPorts.map { $0.port.port })
        return filteredPorts.filter { !activePortNums.contains($0.port) }
    }

    func loadHosts() {
        lastError = nil
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
        lastError = nil
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
            activatedAt[existing.id] = nil
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

    func stopAllForCurrentHost() {
        guard let host = selectedHost else { return }
        let mine = forwardings.filter { $0.host == host.name }
        for fw in mine {
            tunnels.stop(fw.id)
            activatedAt[fw.id] = nil
        }
        forwardings.removeAll { $0.host == host.name }
    }

    func shutdownAll() {
        tunnels.shutdownAll()
        forwardings.removeAll()
    }

    private func startForwarding(host: String, remotePort: Int, localPort: Int) async {
        lastError = nil
        let placeholderID = UUID()
        let placeholder = Forwarding(
            id: placeholderID,
            host: host,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting
        )
        forwardings.append(placeholder)
        activatedAt[placeholderID] = Date()

        do {
            let fw = try await tunnels.start(host: host, remotePort: remotePort, localPort: localPort)
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
            } else {
                forwardings.append(fw)
            }
            // id 전이: placeholder의 활성화 시각을 새 fw.id로 이전
            if let ts = activatedAt.removeValue(forKey: placeholderID) {
                activatedAt[fw.id] = ts
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr) where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            pendingPortConflict = PortConflict(host: host, remotePort: remotePort, attemptedLocal: localPort)
        } catch let error as PortBridgeError {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            lastError = error.errorDescription
        } catch {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
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
