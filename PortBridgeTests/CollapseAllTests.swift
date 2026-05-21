import XCTest
@testable import PortBridge

@MainActor
final class CollapseAllTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.CollapseAllTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeVM(servers: [Server] = []) -> AppViewModel {
        let store = ServerStore(defaults: defaults)
        for server in servers { store.add(server) }
        return AppViewModel(store: store)
    }

    func test_allExpanded_trueWhenAllSectionsExpanded() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        XCTAssertTrue(vm.allExpanded)
    }

    func test_allExpanded_falseWhenOneCollapsed() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        vm.serverSections[0].toggleExpanded()
        XCTAssertFalse(vm.allExpanded)
    }

    func test_allExpanded_trueWhenNoSections() {
        let vm = makeVM()
        XCTAssertTrue(vm.allExpanded, "empty collection should satisfy allSatisfy")
    }

    func test_toggleAllExpanded_collapsesAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2"),
            Server(user: "u", host: "host3")
        ])
        vm.toggleAllExpanded()
        for section in vm.serverSections {
            XCTAssertFalse(section.isExpanded)
        }
        XCTAssertFalse(vm.allExpanded)
    }

    func test_toggleAllExpanded_expandsAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        vm.toggleAllExpanded() // collapse all
        vm.toggleAllExpanded() // expand all
        for section in vm.serverSections {
            XCTAssertTrue(section.isExpanded)
        }
        XCTAssertTrue(vm.allExpanded)
    }

    func test_toggleAllExpanded_whenPartiallyCollapsed_expandsAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2"),
            Server(user: "u", host: "host3")
        ])
        vm.serverSections[1].toggleExpanded() // collapse only #2
        XCTAssertFalse(vm.allExpanded)

        vm.toggleAllExpanded() // should expand all (since not all expanded)
        XCTAssertTrue(vm.allExpanded)
        for section in vm.serverSections {
            XCTAssertTrue(section.isExpanded)
        }
    }
}
