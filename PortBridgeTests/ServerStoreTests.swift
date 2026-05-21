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

    // MARK: - Duplicate detection

    func test_isDuplicate_emptyStore_returnsFalse() {
        let store = ServerStore(defaults: defaults)
        XCTAssertFalse(store.isDuplicate(user: "u", host: "h", port: 22))
    }

    func test_isDuplicate_sameUserHostPort_returnsTrue() {
        let store = ServerStore(defaults: defaults)
        store.add(Server(user: "alice", host: "10.0.0.1", port: 22))
        XCTAssertTrue(store.isDuplicate(user: "alice", host: "10.0.0.1", port: 22))
    }

    func test_isDuplicate_sameHostDifferentUser_returnsFalse() {
        let store = ServerStore(defaults: defaults)
        store.add(Server(user: "alice", host: "10.0.0.1", port: 22))
        XCTAssertFalse(store.isDuplicate(user: "bob", host: "10.0.0.1", port: 22))
    }

    func test_isDuplicate_sameHostDifferentPort_returnsFalse() {
        let store = ServerStore(defaults: defaults)
        store.add(Server(user: "alice", host: "10.0.0.1", port: 22))
        XCTAssertFalse(store.isDuplicate(user: "alice", host: "10.0.0.1", port: 2222))
    }

    /// 편집 시: 자기 자신은 중복으로 잡지 않아야 한다.
    func test_isDuplicate_excludingSelfId_returnsFalse() {
        let store = ServerStore(defaults: defaults)
        let s = Server(user: "alice", host: "10.0.0.1", port: 22)
        store.add(s)
        XCTAssertFalse(
            store.isDuplicate(user: "alice", host: "10.0.0.1", port: 22, excluding: s.id)
        )
    }

    /// 편집 시: 자기 자신이 아닌 다른 서버와 충돌하면 중복.
    func test_isDuplicate_excludingSelf_butAnotherServerClashes_returnsTrue() {
        let store = ServerStore(defaults: defaults)
        let editing = Server(user: "alice", host: "10.0.0.1", port: 22)
        let other = Server(user: "alice", host: "10.0.0.2", port: 22)
        store.add(editing)
        store.add(other)
        // editing을 "10.0.0.2"로 바꾸려는 시도 → other와 충돌
        XCTAssertTrue(
            store.isDuplicate(user: "alice", host: "10.0.0.2", port: 22, excluding: editing.id)
        )
    }
}
