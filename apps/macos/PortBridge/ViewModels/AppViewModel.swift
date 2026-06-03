// PortBridge/ViewModels/AppViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private struct ForwardingRestartEntry {
        let id: UUID
        let remotePort: Int
        let localPort: Int
    }

    private let store: ServerStore
    private let scanner: PortScanner
    private let tunnels: TunnelManaging

    private(set) var serverSections: [ServerSectionViewModel] = []
    private(set) var forwardings: [Forwarding] = [] {
        didSet { recomputeActiveForwardings() }
    }

    private(set) var activeForwardings: [Forwarding] = []
    var pendingPortConflict: PortConflict?
    private(set) var errors: [ErrorToast] = []
    let favorites: FavoriteStore
    let preferences: AppPreferences
    let updates: UpdateChecker
    var searchText: String = "" {
        didSet { normalizedSearchQuery = Self.normalize(searchText) }
    }

    private(set) var normalizedSearchQuery: String = ""

    private let errorDisplayDuration: TimeInterval = 5
    private let maxErrorsShown: Int = 3

    func showError(_ message: String) {
        let toast = ErrorToast(message: message)
        errors.append(toast)
        if errors.count > maxErrorsShown {
            errors.removeFirst(errors.count - maxErrorsShown)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.errorDisplayDuration ?? 5) * 1_000_000_000))
            self?.errors.removeAll { $0.id == toast.id }
        }
    }

    func dismissError(_ id: UUID) {
        errors.removeAll { $0.id == id }
    }

    func matches(_ port: RemotePort) -> Bool {
        let query = normalizedSearchQuery
        guard !query.isEmpty else { return true }
        if String(port.port).contains(query) { return true }
        if let proc = port.processName?.lowercased(), proc.contains(query) { return true }
        return false
    }

    private static func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var allExpanded: Bool {
        serverSections.allSatisfy(\.isExpanded)
    }

    func toggleAllExpanded() {
        let shouldExpand = !allExpanded
        for section in serverSections where section.isExpanded != shouldExpand {
            section.toggleExpanded()
        }
    }

    init(
        store: ServerStore? = nil,
        scanner: PortScanner? = nil,
        tunnels: TunnelManaging? = nil,
        favorites: FavoriteStore? = nil,
        preferences: AppPreferences? = nil,
        updates: UpdateChecker? = nil
    ) {
        self.store = store ?? ServerStore()
        self.scanner = scanner ?? PortScanner(runner: BlockingProcessRunner())
        let manager: TunnelManaging = tunnels ?? TunnelManager()
        self.tunnels = manager
        self.favorites = favorites ?? FavoriteStore()
        self.preferences = preferences ?? AppPreferences.production()
        let resolvedPrefs = self.preferences
        self.updates = updates ?? UpdateChecker(
            fetcher: GitHubReleaseFetcher(
                owner: "yhzion",
                repo: "PortBridge",
                currentAppVersion: Bundle.main.currentVersion?.string ?? "0.0.0"
            ),
            defaults: .standard,
            preferences: resolvedPrefs,
            currentVersion: Bundle.main.currentVersion,
            presenter: UpdatePresenter()
        )
        manager.delegate = self
        rebuildSections()
    }

    private func recomputeActiveForwardings() {
        activeForwardings = forwardings
            .filter { fw in
                switch fw.state {
                case .active, .starting, .error: return true
                case .idle: return false
                }
            }
            .sorted {
                ($0.activatedAt ?? .distantPast) > ($1.activatedAt ?? .distantPast)
            }
    }

    // MARK: - Lookup

    /// View 렌더링 시점에 사용. `Forwarding`이 서버 이름을 복제하지 않고 SSoT(ServerStore)에서 조회.
    func serverDisplayName(for serverId: UUID) -> String? {
        store.servers.first { $0.id == serverId }?.displayName
    }

    // MARK: - Favorites

    func isFavorite(serverId: UUID, port: Int) -> Bool {
        favorites.contains(FavoriteKey(serverId: serverId, remotePort: port))
    }

    func toggleFavorite(serverId: UUID, port: Int) {
        favorites.toggle(FavoriteKey(serverId: serverId, remotePort: port))
    }

    var favoriteRows: [FavoriteRow] {
        favorites.favorites.compactMap { key -> FavoriteRow? in
            guard let server = store.servers.first(where: { $0.id == key.serverId }) else {
                return nil
            }
            let forwarding = forwardings.first(where: {
                $0.serverId == key.serverId && $0.remotePort == key.remotePort
            })
            let section = serverSections.first(where: { $0.server.id == key.serverId })
            let processName = section?.ports.first(where: { $0.port == key.remotePort })?.processName
            let isOffline = if case .offline = section?.scanState { true } else { false }
            let isOnlineConfirmed = if case .loaded = section?.scanState { true } else { false }
            return FavoriteRow(
                id: key,
                serverDisplayName: server.displayName,
                remotePort: key.remotePort,
                localPort: forwarding?.localPort,
                processName: processName,
                state: forwarding?.state ?? .idle,
                isOffline: isOffline,
                isOnlineConfirmed: isOnlineConfirmed
            )
        }
        .sorted { lhs, rhs in
            if lhs.serverDisplayName == rhs.serverDisplayName {
                return lhs.remotePort < rhs.remotePort
            }
            return lhs.serverDisplayName < rhs.serverDisplayName
        }
    }

    var nonFavoriteActive: [Forwarding] {
        activeForwardings.filter { fw in
            !isFavorite(serverId: fw.serverId, port: fw.remotePort)
        }
    }

    /// 앱 시작 시 호출 — preferences.launchAtLogin이 true이면 즐겨찾기를 자동 시작.
    /// `graceSeconds`는 부팅 후 VPN/네트워크 안정화 대기 (production: 5초, 테스트: 0).
    func startFavoritesIfEnabled(graceSeconds: TimeInterval = 5) async {
        guard preferences.launchAtLogin else { return }
        if graceSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(graceSeconds * 1_000_000_000))
        }
        await withTaskGroup(of: Void.self) { group in
            for key in favorites.favorites {
                guard let section = serverSections.first(where: { $0.server.id == key.serverId }) else {
                    continue
                }
                let server = section.server
                let port = key.remotePort
                group.addTask { @MainActor in
                    await self.startForwarding(server: server, remotePort: port, localPort: port)
                }
            }
        }
    }

    // MARK: - Server CRUD

    func addServer(_ server: Server) {
        store.add(server)
        let section = ServerSectionViewModel(server: server, scanner: scanner)
        serverSections.append(section)
        Task { await section.scan() }
    }

    /// 서버 정보를 갱신한다. 접속 식별자(user/host/port)가 변경되었고 활성 forwarding이 있으면
    /// 옛 ssh 프로세스를 정리(stopAndWait)한 뒤 새 서버 정보로 동일한 (remotePort, localPort)
    /// 쌍을 재시작한다. 이름(name)만 바뀐 경우엔 재접속하지 않는다.
    ///
    /// 재시작 실패는 `startForwarding`의 일반 에러 처리(토스트/포트충돌 다이얼로그)에 위임 —
    /// 옛 서버로의 자동 롤백은 수행하지 않는다.
    func updateServer(_ server: Server) async {
        let oldServer = store.servers.first(where: { $0.id == server.id })
        store.update(server)
        serverSections
            .first { $0.server.id == server.id }?
            .update(server: server)

        guard let oldServer, Self.connectionIdentityChanged(old: oldServer, new: server) else {
            return
        }

        let toRestart: [ForwardingRestartEntry] = forwardings
            .filter { $0.serverId == server.id }
            .map { ForwardingRestartEntry(id: $0.id, remotePort: $0.remotePort, localPort: $0.localPort) }
        guard !toRestart.isEmpty else { return }

        forwardings.removeAll { fw in toRestart.contains { $0.id == fw.id } }
        for entry in toRestart {
            await tunnels.stopAndWait(entry.id)
        }
        for entry in toRestart {
            await startForwarding(server: server, remotePort: entry.remotePort, localPort: entry.localPort)
        }
    }

    private static func connectionIdentityChanged(old: Server, new: Server) -> Bool {
        old.user != new.user || old.host != new.host || old.port != new.port
    }

    func deleteServer(_ server: Server) {
        stopAll(for: server.id)
        store.delete(server)
        serverSections.removeAll { $0.server.id == server.id }
    }

    /// `(user, host, port)` 3튜플 기준 중복 여부. 편집 시 `excluding`에 자기 id를 전달.
    func isDuplicateServer(user: String, host: String, port: Int, excluding id: UUID? = nil) -> Bool {
        store.isDuplicate(user: user, host: host, port: port, excluding: id)
    }

    // MARK: - Scanning

    func scanAll() async {
        await withTaskGroup(of: Void.self) { group in
            for section in serverSections {
                group.addTask { await section.scan() }
            }
        }
    }

    // MARK: - Menu bar (right-click toggle)

    /// 메뉴바 아이콘 ON 판정 + 우클릭 일괄토글의 방향 결정에 쓰는 파생 상태.
    /// 즐겨찾기 여부와 무관하게 active/starting 포워딩이 하나라도 있으면 true.
    var isAnyForwardingActive: Bool {
        forwardings.contains { fw in
            switch fw.state {
            case .active, .starting: return true
            case .idle, .error: return false
            }
        }
    }

    /// 메뉴바 우클릭 핸들러 — 빠른 일괄 토글 (Amphetamine 패턴).
    ///
    /// 규칙 (비대칭):
    /// - 하나라도 연결 중 (isAnyForwardingActive == true) → 즐겨찾기 여부와 무관하게 전부 OFF
    /// - 모두 OFF                                          → 즐겨찾기만 ON
    ///
    /// 단일 forwarding 토글은 `toggleForwarding(serverId:for:)`를 사용하면 됩니다.
    /// 그 함수가 idempotent하지 않다는 점에 주의 — 같은 상태로 호출하면 반대로 뒤집습니다.
    /// 따라서 방향별로 대상을 미리 걸러 의도한 방향으로만 뒤집습니다.
    func toggleAll() async {
        let targets: [(serverId: UUID, port: RemotePort)] = if isAnyForwardingActive {
            // OFF: 즐겨찾기 여부와 무관하게 active/starting 포워딩 전부 해제.
            forwardings.compactMap { fw in
                switch fw.state {
                case .active, .starting:
                    return (serverId: fw.serverId, port: RemotePort(port: fw.remotePort, address: "0.0.0.0", processName: nil))
                case .idle, .error:
                    return nil
                }
            }
        } else {
            // ON: 즐겨찾기만 연결 시도 (아직 연결 안 된 즐겨찾기).
            favoriteRows.compactMap { row in
                switch row.state {
                case .idle, .error:
                    let port = RemotePort(port: row.remotePort, address: "0.0.0.0", processName: row.processName)
                    return (serverId: row.id.serverId, port: port)
                case .active, .starting:
                    return nil
                }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                let serverId = target.serverId
                let port = target.port
                group.addTask { @MainActor in
                    await self.toggleForwarding(serverId: serverId, for: port)
                }
            }
        }
    }

    // MARK: - Forwarding

    func toggleForwarding(serverId: UUID, for port: RemotePort) async {
        if let existing = forwardings.first(where: { $0.serverId == serverId && $0.remotePort == port.port }) {
            await tunnels.stopAndWait(existing.id)
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
        }
        forwardings.removeAll { $0.serverId == serverId }
    }

    /// UI의 "모두 끄기" 액션 — 사용자에게 표시되는 모든 활성/시작중/에러 forwarding을 중단.
    /// `shutdownAll()`은 앱 종료 시점용이라 의도 분리를 위해 별도 메소드로 둡니다.
    func stopAllActiveForwardings() {
        let ids = Set(activeForwardings.map(\.id))
        guard !ids.isEmpty else { return }
        for id in ids {
            tunnels.stop(id)
        }
        forwardings.removeAll { ids.contains($0.id) }
    }

    func shutdownAll() {
        tunnels.shutdownAll()
        forwardings.removeAll()
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
        let placeholderID = UUID()
        let activated = Date()
        let placeholder = Forwarding(
            id: placeholderID,
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting,
            activatedAt: activated
        )
        forwardings.append(placeholder)

        do {
            var fw = try await tunnels.start(server: server, remotePort: remotePort, localPort: localPort)
            fw.activatedAt = activated
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
            } else {
                // placeholder was removed while start() was in-flight (user cancelled)
                tunnels.stop(fw.id)
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr)
            where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            pendingPortConflict = PortConflict(
                serverId: server.id,
                remotePort: remotePort,
                attemptedLocal: localPort
            )
        } catch let error as PortBridgeError {
            forwardings.removeAll { $0.id == placeholderID }
            showError(error.errorDescription ?? error.localizedDescription)
        } catch {
            forwardings.removeAll { $0.id == placeholderID }
            showError(error.localizedDescription)
        }
    }
}

struct ErrorToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct PortConflict: Identifiable, Equatable {
    let id = UUID()
    let serverId: UUID
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

struct FavoriteRow: Identifiable, Equatable {
    let id: FavoriteKey
    let serverDisplayName: String
    let remotePort: Int
    let localPort: Int?
    let processName: String?
    let state: Forwarding.State
    let isOffline: Bool
    /// 서버의 마지막 스캔이 성공해 도달 가능함이 확정된 경우(`scanState == .loaded`).
    /// 메뉴바는 이것이 false이고 신뢰 가능한 연결도 아닐 때 행을 흐리게 표시한다.
    let isOnlineConfirmed: Bool
}

#if DEBUG
    extension AppViewModel {
        // Test-only helper to inject an active forwarding state.
        // swiftlint:disable:next identifier_name
        func _test_injectActiveForwarding(serverId: UUID, remotePort: Int, localPort: Int? = nil) {
            let fw = Forwarding(
                serverId: serverId,
                remotePort: remotePort,
                localPort: localPort ?? remotePort,
                state: .active,
                activatedAt: Date()
            )
            forwardings.append(fw)
        }
    }
#endif
