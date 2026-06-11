@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelSearchSubmitTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AVMSearchSubmit.\(UUID().uuidString)"
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
        AppViewModel(
            store: ServerStore(defaults: defaults),
            scanner: PortScanner(runner: MockFfiCommandRunner()),
            tunnels: MockTunnelManager(),
            favorites: FavoriteStore(defaults: defaults),
            preferences: AppPreferences(
                defaults: defaults,
                applyShowInDock: { _ in },
                applyLaunchAtLogin: { _ in true },
                readLaunchAtLogin: { false }
            )
        )
    }

    private func loadPorts(_ vm: AppViewModel, serverId: UUID, ports: [RemotePort]) {
        vm.serverSections
            .first { $0.server.id == serverId }?
            ._test_setScanState(.loaded(ports))
    }

    func test_singleSearchMatch_exactlyOneResult_returnsIt() {
        let vm = makeViewModel()
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        loadPorts(vm, serverId: server.id, ports: [
            RemotePort(port: 5432, address: "0.0.0.0", processName: "postgres"),
            RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx")
        ])
        vm.searchText = "5432"

        let match = vm.singleSearchMatch()
        XCTAssertEqual(match?.serverId, server.id)
        XCTAssertEqual(match?.port.port, 5432)
    }

    func test_singleSearchMatch_multipleResults_returnsNil() {
        let vm = makeViewModel()
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        loadPorts(vm, serverId: server.id, ports: [
            RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx"),
            RemotePort(port: 8081, address: "0.0.0.0", processName: "nginx")
        ])
        vm.searchText = "nginx"

        XCTAssertNil(vm.singleSearchMatch())
    }

    func test_singleSearchMatch_emptyQuery_returnsNil() {
        let vm = makeViewModel()
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        loadPorts(vm, serverId: server.id, ports: [
            RemotePort(port: 5432, address: "0.0.0.0", processName: "postgres")
        ])
        vm.searchText = ""

        XCTAssertNil(vm.singleSearchMatch())
    }

    func test_submitSearch_singleMatch_startsForwarding() async {
        let mockTunnels = MockTunnelManager()
        let vm = AppViewModel(
            store: ServerStore(defaults: defaults),
            scanner: PortScanner(runner: MockFfiCommandRunner()),
            tunnels: mockTunnels,
            favorites: FavoriteStore(defaults: defaults),
            preferences: AppPreferences(
                defaults: defaults,
                applyShowInDock: { _ in },
                applyLaunchAtLogin: { _ in true },
                readLaunchAtLogin: { false }
            )
        )
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        loadPorts(vm, serverId: server.id, ports: [
            RemotePort(port: 5432, address: "0.0.0.0", processName: "postgres")
        ])
        mockTunnels.nextResult = Forwarding(
            serverId: server.id,
            remotePort: 5432,
            localPort: 5432,
            state: .active
        )
        vm.searchText = "5432"

        await vm.submitSearch()

        XCTAssertEqual(mockTunnels.startCalls.count, 1)
        XCTAssertEqual(mockTunnels.startCalls.first?.remotePort, 5432)
    }

    func test_submitSearch_noSingleMatch_doesNothing() async {
        let mockTunnels = MockTunnelManager()
        let vm = AppViewModel(
            store: ServerStore(defaults: defaults),
            scanner: PortScanner(runner: MockFfiCommandRunner()),
            tunnels: mockTunnels,
            favorites: FavoriteStore(defaults: defaults),
            preferences: AppPreferences(
                defaults: defaults,
                applyShowInDock: { _ in },
                applyLaunchAtLogin: { _ in true },
                readLaunchAtLogin: { false }
            )
        )
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        loadPorts(vm, serverId: server.id, ports: [
            RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx"),
            RemotePort(port: 8081, address: "0.0.0.0", processName: "nginx")
        ])
        vm.searchText = "nginx"

        await vm.submitSearch()

        XCTAssertTrue(mockTunnels.startCalls.isEmpty)
    }
}
