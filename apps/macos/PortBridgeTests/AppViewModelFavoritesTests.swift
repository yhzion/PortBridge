@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelFavoritesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AVMFavorites.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeViewModel(tunnels: MockTunnelManager? = nil) -> AppViewModel {
        let serverStore = ServerStore(defaults: defaults)
        let favoriteStore = FavoriteStore(defaults: defaults)
        let preferences = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        return AppViewModel(
            store: serverStore,
            scanner: PortScanner(runner: MockFfiCommandRunner()),
            tunnels: tunnels ?? MockTunnelManager(),
            favorites: favoriteStore,
            preferences: preferences
        )
    }

    func test_isFavorite_falseInitially() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isFavorite(serverId: UUID(), port: 5432))
    }

    func test_toggleFavorite_addsThenRemoves() {
        let vm = makeViewModel()
        let serverId = UUID()
        vm.toggleFavorite(serverId: serverId, port: 5432)
        XCTAssertTrue(vm.isFavorite(serverId: serverId, port: 5432))
        vm.toggleFavorite(serverId: serverId, port: 5432)
        XCTAssertFalse(vm.isFavorite(serverId: serverId, port: 5432))
    }

    func test_toggleFavorite_independentPerServerAndPort() {
        let vm = makeViewModel()
        let serverA = UUID()
        let serverB = UUID()
        vm.toggleFavorite(serverId: serverA, port: 5432)
        XCTAssertTrue(vm.isFavorite(serverId: serverA, port: 5432))
        XCTAssertFalse(vm.isFavorite(serverId: serverB, port: 5432))
        XCTAssertFalse(vm.isFavorite(serverId: serverA, port: 5433))
    }

    func test_favoriteRows_emptyWhenNoFavorites() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.favoriteRows.isEmpty)
    }

    func test_favoriteRows_includesIdleFavorite_serverNameAndPortOnly() {
        let vm = makeViewModel()
        let server = Server(name: "db-prod", user: "ubuntu", host: "10.0.0.1")
        vm.addServer(server)
        vm.toggleFavorite(serverId: server.id, port: 5432)

        let rows = vm.favoriteRows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.serverDisplayName, "db-prod (10.0.0.1)")
        XCTAssertEqual(rows.first?.remotePort, 5432)
        XCTAssertNil(rows.first?.localPort)
        XCTAssertEqual(rows.first?.state, .idle)
    }

    func test_favoriteRows_orderedByServerDisplayNameThenPort() {
        let vm = makeViewModel()
        let alpha = Server(name: "alpha", user: "u", host: "a")
        let beta = Server(name: "beta", user: "u", host: "b")
        vm.addServer(beta)
        vm.addServer(alpha)
        vm.toggleFavorite(serverId: beta.id, port: 6379)
        vm.toggleFavorite(serverId: alpha.id, port: 5432)
        vm.toggleFavorite(serverId: alpha.id, port: 5433)

        let names = vm.favoriteRows.map(\.serverDisplayName)
        let ports = vm.favoriteRows.map(\.remotePort)
        XCTAssertEqual(names, ["alpha (a)", "alpha (a)", "beta (b)"])
        XCTAssertEqual(ports, [5432, 5433, 6379])
    }

    func test_favoriteRows_isOffline_tracksSectionScanState() {
        let vm = makeViewModel()
        let server = Server(name: "db-prod", user: "ubuntu", host: "10.0.0.1")
        vm.addServer(server)
        vm.toggleFavorite(serverId: server.id, port: 5432)
        let section = vm.serverSections.first { $0.id == server.id }

        section?._test_setScanState(.loaded([]))
        XCTAssertEqual(vm.favoriteRows.first?.isOffline, false)

        section?._test_setScanState(.offline(isRetrying: false))
        XCTAssertEqual(vm.favoriteRows.first?.isOffline, true)

        section?._test_setScanState(.loaded([]))
        XCTAssertEqual(vm.favoriteRows.first?.isOffline, false, "isOffline must clear when the server comes back online")
    }

    func test_favoriteRows_offlineServer_isOfflineEvenWhenForwardingActive() {
        // Repro: an offline server can carry a stale/fake `.active` forwarding
        // (ssh hangs in TCP connect with no ConnectTimeout, passes the 2s grace).
        // The menubar must not render it as connected — it must reflect offline.
        let vm = makeViewModel()
        let server = Server(name: "db-prod", user: "ubuntu", host: "10.0.0.1")
        vm.addServer(server)
        vm.toggleFavorite(serverId: server.id, port: 5432)
        vm._test_injectActiveForwarding(serverId: server.id, remotePort: 5432)
        vm.serverSections.first { $0.id == server.id }?._test_setScanState(.offline(isRetrying: false))

        let row = vm.favoriteRows.first
        XCTAssertEqual(row?.isOffline, true)
        XCTAssertEqual(row?.state, .active, "raw forwarding state is preserved; the view layer suppresses ● when offline")
    }

    func test_favoriteRows_orphanedFavorite_excluded() {
        let vm = makeViewModel()
        let ghostServerId = UUID()
        vm.toggleFavorite(serverId: ghostServerId, port: 5432)
        XCTAssertTrue(vm.favoriteRows.isEmpty)
    }

    func test_nonFavoriteActive_emptyWhenAllActiveAreFavorites() {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 80)
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 80)
        XCTAssertTrue(vm.nonFavoriteActive.isEmpty)
    }

    func test_nonFavoriteActive_includesNonFavoriteActive() {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 9000)
        let active = vm.nonFavoriteActive
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.remotePort, 9000)
    }

    func test_startFavoritesIfEnabled_skipsWhenLaunchAtLoginOff() async {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 5432)
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        XCTAssertTrue(vm.activeForwardings.isEmpty)
    }

    func test_startFavoritesIfEnabled_startsFavoritesWhenEnabled() async {
        let mockTunnels = MockTunnelManager()
        let vm = makeViewModel(tunnels: mockTunnels)
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        mockTunnels.nextResult = Forwarding(
            serverId: s.id,
            remotePort: 5432,
            localPort: 5432,
            state: .active
        )
        vm.preferences.launchAtLogin = true
        vm.toggleFavorite(serverId: s.id, port: 5432)
        vm.toggleFavorite(serverId: s.id, port: 6379)
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        XCTAssertEqual(mockTunnels.startCalls.count, 2)
    }

    func test_startFavoritesIfEnabled_skipsOrphanedFavorites() async {
        let mockTunnels = MockTunnelManager()
        let vm = makeViewModel(tunnels: mockTunnels)
        vm.preferences.launchAtLogin = true
        let ghostServerId = UUID()
        vm.toggleFavorite(serverId: ghostServerId, port: 5432)
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        XCTAssertTrue(mockTunnels.startCalls.isEmpty)
    }

    // MARK: - toggleAll (right-click) behavior

    func test_toggleAll_offThenOn_restartsIdleFavorite() async {
        let mockTunnels = MockTunnelManager()
        let vm = makeViewModel(tunnels: mockTunnels)
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 8080)

        // Simulate connected state
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 8080)
        XCTAssertTrue(vm.isAnyForwardingActive)

        // OFF: should disconnect active forwardings
        await vm.toggleAll()
        XCTAssertFalse(vm.isAnyForwardingActive)
        XCTAssertTrue(vm.forwardings.isEmpty)
        XCTAssertEqual(mockTunnels.stopAndWaitCalls.count, 1)

        // ON: should reconnect idle favorites
        mockTunnels.nextResult = Forwarding(
            serverId: s.id,
            remotePort: 8080,
            localPort: 8080,
            state: .active
        )
        await vm.toggleAll()

        XCTAssertTrue(vm.isAnyForwardingActive, "ON toggleAll should reconnect favorite")
        XCTAssertEqual(vm.forwardings.count, 1)
        XCTAssertEqual(mockTunnels.startCalls.count, 1, "tunnels.start should be called once for ON")
    }

    func test_toggleAll_offThenOn_withNonFavoriteActiveOnly() async {
        let mockTunnels = MockTunnelManager()
        let vm = makeViewModel(tunnels: mockTunnels)
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)

        // Non-favorite active forwarding
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 9000)
        XCTAssertTrue(vm.isAnyForwardingActive)

        // OFF
        await vm.toggleAll()
        XCTAssertFalse(vm.isAnyForwardingActive)
        XCTAssertTrue(vm.forwardings.isEmpty)

        // ON: no favorites, so nothing to start
        await vm.toggleAll()
        XCTAssertFalse(vm.isAnyForwardingActive)
        XCTAssertTrue(vm.forwardings.isEmpty)
        XCTAssertTrue(mockTunnels.startCalls.isEmpty)
    }
}
