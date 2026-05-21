import XCTest
@testable import PortBridge

@MainActor
final class FavoriteStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.FavoriteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_add_insertsFavorite() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        XCTAssertTrue(store.contains(key))
        XCTAssertEqual(store.favorites.count, 1)
    }

    func test_add_isIdempotent() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        store.add(key)
        XCTAssertEqual(store.favorites.count, 1)
    }

    func test_remove_deletesFavorite() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        store.remove(key)
        XCTAssertFalse(store.contains(key))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func test_toggle_addsThenRemoves() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.toggle(key)
        XCTAssertTrue(store.contains(key))
        store.toggle(key)
        XCTAssertFalse(store.contains(key))
    }

    func test_persistence_survivesNewInstance() {
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        let store1 = FavoriteStore(defaults: defaults)
        store1.add(key)

        let store2 = FavoriteStore(defaults: defaults)
        XCTAssertTrue(store2.contains(key))
    }

    func test_multipleKeys_storedIndependently() {
        let store = FavoriteStore(defaults: defaults)
        let serverA = UUID()
        let serverB = UUID()
        store.add(FavoriteKey(serverId: serverA, remotePort: 5432))
        store.add(FavoriteKey(serverId: serverB, remotePort: 5432))
        store.add(FavoriteKey(serverId: serverA, remotePort: 8080))
        XCTAssertEqual(store.favorites.count, 3)
    }
}
