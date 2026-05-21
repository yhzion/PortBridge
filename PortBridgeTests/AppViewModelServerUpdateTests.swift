import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelServerUpdateTests: XCTestCase {
    private let testKey = "portbridge.servers"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func test_updateServer_refreshesVisibleSectionServerInfo() {
        let store = ServerStore()
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
        vm.updateServer(updated)

        XCTAssertEqual(store.servers.first?.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.name, "staging")
        XCTAssertEqual(vm.serverSections.first?.server.user, "deploy")
        XCTAssertEqual(vm.serverSections.first?.server.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.port, 2222)
    }
}
