import XCTest
@testable import PortBridge

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

    private func makeViewModel() -> AppViewModel {
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
            tunnels: MockTunnelManager(),
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
}
