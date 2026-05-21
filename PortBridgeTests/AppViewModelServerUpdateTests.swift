import XCTest
@testable import PortBridge

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

    func test_updateServer_refreshesVisibleSectionServerInfo() {
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
        vm.updateServer(updated)

        XCTAssertEqual(store.servers.first?.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.name, "staging")
        XCTAssertEqual(vm.serverSections.first?.server.user, "deploy")
        XCTAssertEqual(vm.serverSections.first?.server.host, "new.example")
        XCTAssertEqual(vm.serverSections.first?.server.port, 2222)
    }
}
