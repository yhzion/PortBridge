@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelServerUpdateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppViewModelServerUpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_updateServer_refreshesVisibleSectionServerInfo() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "ubuntu", host: "old.example", port: 22)
        store.add(original)
        let vm = AppViewModel(store: store)

        let updated = Server(
            id: original.id,
            name: "staging",
            user: "deploy",
            host: "new.example",
            port: 2222
        )
        await vm.updateServer(updated)

        XCTAssertEqual(store.servers.first?.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.name, "staging")
        XCTAssertEqual(vm.serverSections.first?.server.user, "deploy")
        XCTAssertEqual(vm.serverSections.first?.server.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.port, 2222)
    }

    // MARK: - Auto-reconnect on connection-identity change

    /// host 변경 시 활성 forwarding은 새 host의 ssh 인자로 재시작되어야 한다.
    /// "수정한 IP가 반영 안 됨"으로 보이던 증상의 근본 해결.
    func test_updateServer_whenHostChanges_restartsActiveForwardingsWithNewServer() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "ubuntu", host: "old.example", port: 22)
        store.add(original)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        let firstFw = Forwarding(serverId: original.id, remotePort: 8080, localPort: 8080, state: .active)
        mock.nextResult = firstFw
        await vm.toggleForwarding(
            serverId: original.id,
            for: RemotePort(port: 8080, address: "0.0.0.0", processName: nil)
        )
        XCTAssertEqual(mock.startCalls.count, 1)
        XCTAssertEqual(mock.startCalls[0].server.host, "old.example")

        let updated = Server(id: original.id, name: "prod", user: "ubuntu", host: "new.example", port: 22)
        let secondFw = Forwarding(serverId: original.id, remotePort: 8080, localPort: 8080, state: .active)
        mock.nextResult = secondFw

        await vm.updateServer(updated)

        XCTAssertTrue(
            mock.stopAndWaitCalls.contains(firstFw.id),
            "옛 forwarding이 stopAndWait로 정리되어야 함; stopAndWaitCalls=\(mock.stopAndWaitCalls)"
        )
        XCTAssertEqual(mock.startCalls.count, 2, "새 host로 재시작 호출이 있어야 함")
        XCTAssertEqual(mock.startCalls[1].server.host, "new.example")
        XCTAssertEqual(mock.startCalls[1].remotePort, 8080)
        XCTAssertEqual(mock.startCalls[1].localPort, 8080)
    }

    /// user 변경도 host 변경과 동일하게 재접속을 트리거해야 한다.
    func test_updateServer_whenUserChanges_restartsActiveForwardingsWithNewServer() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "alice", host: "h.example", port: 22)
        store.add(original)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        let firstFw = Forwarding(serverId: original.id, remotePort: 5432, localPort: 5432, state: .active)
        mock.nextResult = firstFw
        await vm.toggleForwarding(
            serverId: original.id,
            for: RemotePort(port: 5432, address: "0.0.0.0", processName: nil)
        )

        let updated = Server(id: original.id, name: "prod", user: "bob", host: "h.example", port: 22)
        mock.nextResult = Forwarding(serverId: original.id, remotePort: 5432, localPort: 5432, state: .active)

        await vm.updateServer(updated)

        XCTAssertTrue(mock.stopAndWaitCalls.contains(firstFw.id))
        XCTAssertEqual(mock.startCalls.count, 2)
        XCTAssertEqual(mock.startCalls[1].server.user, "bob")
    }

    /// port 변경도 재접속을 트리거해야 한다.
    func test_updateServer_whenPortChanges_restartsActiveForwardingsWithNewServer() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "u", host: "h.example", port: 22)
        store.add(original)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        let firstFw = Forwarding(serverId: original.id, remotePort: 80, localPort: 80, state: .active)
        mock.nextResult = firstFw
        await vm.toggleForwarding(
            serverId: original.id,
            for: RemotePort(port: 80, address: "0.0.0.0", processName: nil)
        )

        let updated = Server(id: original.id, name: "prod", user: "u", host: "h.example", port: 2222)
        mock.nextResult = Forwarding(serverId: original.id, remotePort: 80, localPort: 80, state: .active)

        await vm.updateServer(updated)

        XCTAssertTrue(mock.stopAndWaitCalls.contains(firstFw.id))
        XCTAssertEqual(mock.startCalls.count, 2)
        XCTAssertEqual(mock.startCalls[1].server.port, 2222)
    }

    /// 이름(name)만 바뀌면 접속에 영향이 없으므로 활성 forwarding을 건드리지 않는다.
    func test_updateServer_whenOnlyNameChanges_doesNotRestartForwardings() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "u", host: "h.example", port: 22)
        store.add(original)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        let firstFw = Forwarding(serverId: original.id, remotePort: 8080, localPort: 8080, state: .active)
        mock.nextResult = firstFw
        await vm.toggleForwarding(
            serverId: original.id,
            for: RemotePort(port: 8080, address: "0.0.0.0", processName: nil)
        )
        XCTAssertEqual(mock.startCalls.count, 1)

        let renamed = Server(id: original.id, name: "staging", user: "u", host: "h.example", port: 22)
        await vm.updateServer(renamed)

        XCTAssertTrue(mock.stopAndWaitCalls.isEmpty, "이름만 바뀌면 stop 호출 없어야 함")
        XCTAssertEqual(mock.startCalls.count, 1, "재접속 호출 없어야 함")
        XCTAssertEqual(vm.serverSections.first?.server.name, "staging")
    }

    // MARK: - Duplicate guard (facade over ServerStore)

    func test_isDuplicateServer_returnsTrueWhenTripleMatches() {
        let store = ServerStore(defaults: defaults)
        store.add(Server(user: "alice", host: "10.0.0.1", port: 22))
        let vm = AppViewModel(store: store)
        XCTAssertTrue(vm.isDuplicateServer(user: "alice", host: "10.0.0.1", port: 22))
    }

    func test_isDuplicateServer_excludingSelf_returnsFalseForSelf() {
        let store = ServerStore(defaults: defaults)
        let s = Server(user: "alice", host: "10.0.0.1", port: 22)
        store.add(s)
        let vm = AppViewModel(store: store)
        XCTAssertFalse(
            vm.isDuplicateServer(user: "alice", host: "10.0.0.1", port: 22, excluding: s.id)
        )
    }

    /// 활성 forwarding이 없으면 host 변경에도 재접속할 게 없다 — 단순 갱신만.
    func test_updateServer_whenNoActiveForwardings_skipsReconnect() async {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "u", host: "old.example", port: 22)
        store.add(original)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        let updated = Server(id: original.id, name: "prod", user: "u", host: "new.example", port: 22)
        await vm.updateServer(updated)

        XCTAssertTrue(mock.startCalls.isEmpty)
        XCTAssertTrue(mock.stopAndWaitCalls.isEmpty)
        XCTAssertEqual(vm.serverSections.first?.server.host, "new.example")
    }
}
