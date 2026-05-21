// PortBridge/ViewModels/AppViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private let store: ServerStore
    private let scanner: PortScanner
    private let tunnels: TunnelManager

    private(set) var serverSections: [ServerSectionViewModel] = []
    var forwardings: [Forwarding] = []
    private(set) var activatedAt: [UUID: Date] = [:]
    var pendingPortConflict: PortConflict?
    var lastError: String?
    var searchText: String = ""

    func matches(_ port: RemotePort) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        if String(port.port).contains(query) { return true }
        if let proc = port.processName?.lowercased(), proc.contains(query) { return true }
        return false
    }

    var allExpanded: Bool {
        serverSections.allSatisfy(\.isExpanded)
    }

    func toggleAllExpanded() {
        let shouldExpand = !allExpanded
        for section in serverSections {
            if section.isExpanded != shouldExpand {
                section.toggleExpanded()
            }
        }
    }

    init(
        store: ServerStore = ServerStore(),
        scanner: PortScanner = PortScanner(runner: ProcessCommandRunner()),
        tunnels: TunnelManager? = nil
    ) {
        self.store = store
        self.scanner = scanner
        let t = tunnels ?? TunnelManager()
        self.tunnels = t
        t.delegate = self
        rebuildSections()
    }

    var activeForwardings: [Forwarding] {
        forwardings
            .filter { fw in
                switch fw.state {
                case .active, .starting, .error: return true
                case .idle: return false
                }
            }
            .sorted {
                activatedAt[$0.id, default: .distantPast] > activatedAt[$1.id, default: .distantPast]
            }
    }

    // MARK: - Server CRUD

    func addServer(_ server: Server) {
        store.add(server)
        let section = ServerSectionViewModel(server: server, scanner: scanner)
        serverSections.append(section)
        Task { await section.scan() }
    }

    func updateServer(_ server: Server) {
        store.update(server)
        rebuildSections()
    }

    func deleteServer(_ server: Server) {
        stopAll(for: server.id)
        store.delete(server)
        serverSections.removeAll { $0.server.id == server.id }
    }

    // MARK: - Scanning

    func scanAll() async {
        await withTaskGroup(of: Void.self) { group in
            for section in serverSections {
                group.addTask { await section.scan() }
            }
        }
    }

    // MARK: - Forwarding

    func toggleForwarding(serverId: UUID, for port: RemotePort) async {
        if let existing = forwardings.first(where: { $0.serverId == serverId && $0.remotePort == port.port }) {
            tunnels.stop(existing.id)
            activatedAt[existing.id] = nil
            forwardings.removeAll { $0.id == existing.id }
            return
        }
        guard let section = serverSections.first(where: { $0.server.id == serverId }) else { return }
        await startForwarding(server: section.server, remotePort: port.port, localPort: port.port)
    }

    func resolveConflict(with newLocalPort: Int) async {
        guard let pending = pendingPortConflict else { return }
        pendingPortConflict = nil
        guard let section = serverSections.first(where: { $0.server.id == pending.serverId }) else { return }
        await startForwarding(server: section.server, remotePort: pending.remotePort, localPort: newLocalPort)
    }

    func stopAll(for serverId: UUID) {
        let mine = forwardings.filter { $0.serverId == serverId }
        for fw in mine {
            tunnels.stop(fw.id)
            activatedAt[fw.id] = nil
        }
        forwardings.removeAll { $0.serverId == serverId }
    }

    func shutdownAll() {
        tunnels.shutdownAll()
        forwardings.removeAll()
        activatedAt.removeAll()
    }

    // MARK: - Private

    private func rebuildSections() {
        let existing = Dictionary(uniqueKeysWithValues: serverSections.map { ($0.server.id, $0) })
        serverSections = store.servers.map { server in
            if let section = existing[server.id] {
                section.update(server: server)
                return section
            }
            return ServerSectionViewModel(server: server, scanner: scanner)
        }
    }

    private func startForwarding(server: Server, remotePort: Int, localPort: Int) async {
        lastError = nil
        let placeholderID = UUID()
        let placeholder = Forwarding(
            id: placeholderID,
            serverId: server.id,
            serverDisplayName: server.displayName,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting
        )
        forwardings.append(placeholder)
        activatedAt[placeholderID] = Date()

        do {
            let fw = try await tunnels.start(server: server, remotePort: remotePort, localPort: localPort)
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
                if let ts = activatedAt.removeValue(forKey: placeholderID) {
                    activatedAt[fw.id] = ts
                }
            } else {
                // placeholder was removed while start() was in-flight (user cancelled)
                tunnels.stop(fw.id)
                activatedAt[placeholderID] = nil
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr)
            where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            pendingPortConflict = PortConflict(
                serverId: server.id,
                serverDisplayName: server.displayName,
                remotePort: remotePort,
                attemptedLocal: localPort
            )
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
    let serverId: UUID
    let serverDisplayName: String
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
