import XCTest
@testable import PortBridge

@MainActor
final class ServerStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.ServerStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_add_appendsServer() {
        let store = ServerStore(defaults: defaults)
        let s = Server(user: "u", host: "h")
        store.add(s)
        XCTAssertEqual(store.servers.count, 1)
        XCTAssertEqual(store.servers.first?.id, s.id)
    }

    func test_update_modifiesExisting() {
        let store = ServerStore(defaults: defaults)
        var s = Server(user: "u", host: "h")
        store.add(s)
        s.name = "updated"
        store.update(s)
        XCTAssertEqual(store.servers.first?.name, "updated")
    }

    func test_delete_removesServer() {
        let store = ServerStore(defaults: defaults)
        let s = Server(user: "u", host: "h")
        store.add(s)
        store.delete(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_persistence_survivesNewInstance() {
        let s = Server(name: "prod", user: "ubuntu", host: "10.0.0.1")
        let store1 = ServerStore(defaults: defaults)
        store1.add(s)

        let store2 = ServerStore(defaults: defaults)
        XCTAssertEqual(store2.servers.first?.id, s.id)
        XCTAssertEqual(store2.servers.first?.name, "prod")
    }

    func test_update_unknownId_doesNothing() {
        let store = ServerStore(defaults: defaults)
        let s = Server(user: "u", host: "h")
        store.update(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_order_preserved() {
        let store = ServerStore(defaults: defaults)
        let a = Server(user: "u", host: "a")
        let b = Server(user: "u", host: "b")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.servers.map(\.host), ["a", "b"])
    }
}
