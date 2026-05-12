import XCTest
@testable import PortBridge

final class ServerStoreTests: XCTestCase {
    private let testKey = "portbridge.servers"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    func test_add_appendsServer() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.add(s)
        XCTAssertEqual(store.servers.count, 1)
        XCTAssertEqual(store.servers.first?.id, s.id)
    }

    func test_update_modifiesExisting() {
        let store = ServerStore()
        var s = Server(user: "u", host: "h")
        store.add(s)
        s.name = "updated"
        store.update(s)
        XCTAssertEqual(store.servers.first?.name, "updated")
    }

    func test_delete_removesServer() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.add(s)
        store.delete(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_persistence_survivesNewInstance() {
        let s = Server(name: "prod", user: "ubuntu", host: "10.0.0.1")
        let store1 = ServerStore()
        store1.add(s)

        let store2 = ServerStore()
        XCTAssertEqual(store2.servers.first?.id, s.id)
        XCTAssertEqual(store2.servers.first?.name, "prod")
    }

    func test_update_unknownId_doesNothing() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.update(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_order_preserved() {
        let store = ServerStore()
        let a = Server(user: "u", host: "a")
        let b = Server(user: "u", host: "b")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.servers.map(\.host), ["a", "b"])
    }
}
