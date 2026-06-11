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
            scanner: PortScanner(runner: MockCommandRunner()),
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

    func test_toggleAllFavorites_startsAllWhenNoneActive() async {
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
        vm.toggleFavorite(serverId: s.id, port: 5432)
        vm.toggleFavorite(serverId: s.id, port: 6379)
        await vm.toggleAllFavorites()
        XCTAssertEqual(mockTunnels.startCalls.count, 2)
        XCTAssertTrue(mockTunnels.stopCalls.isEmpty)
    }

    func test_toggleAllFavorites_stopsOnlyActiveWhenAnyActive() async {
        let mockTunnels = MockTunnelManager()
        let vm = makeViewModel(tunnels: mockTunnels)
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 5432)
        vm.toggleFavorite(serverId: s.id, port: 6379)
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 5432)
        await vm.toggleAllFavorites()
        XCTAssertTrue(mockTunnels.startCalls.isEmpty)
        XCTAssertEqual(mockTunnels.stopCalls.count, 1)
        XCTAssertTrue(vm.activeForwardings.isEmpty)
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
}
