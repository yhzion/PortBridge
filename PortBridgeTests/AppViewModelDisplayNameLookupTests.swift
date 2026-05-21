import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelDisplayNameLookupTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppViewModelDisplayNameLookupTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_serverDisplayName_returnsCurrentNameAfterRename() {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "ubuntu", host: "10.0.0.1", port: 22)
        store.add(original)
        let vm = AppViewModel(store: store)

        let renamed = Server(id: original.id, name: "production", user: "ubuntu", host: "10.0.0.1", port: 22)
        vm.updateServer(renamed)

        XCTAssertEqual(vm.serverDisplayName(for: original.id), "production (10.0.0.1)")
    }

    func test_serverDisplayName_returnsNilForUnknownId() {
        let vm = AppViewModel(store: ServerStore(defaults: defaults))
        XCTAssertNil(vm.serverDisplayName(for: UUID()))
    }
}
