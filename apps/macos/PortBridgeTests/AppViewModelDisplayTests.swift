@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelDisplayTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AVMDisplay.\(UUID().uuidString)"
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

    func test_display_activeForwarding_injectsHostAndArrow() {
        let vm = makeViewModel()
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        let fw = Forwarding(serverId: server.id, remotePort: 5432, localPort: 6000, state: .active)
        let d = vm.display(for: fw)
        XCTAssertEqual(d.status, .active)
        XCTAssertEqual(d.host, "db (10.0.0.1)")
        XCTAssertEqual(d.localPort, 6000)
        XCTAssertEqual(d.line, "db (10.0.0.1):5432 → :6000") // 스캔 없으니 process는 없음
    }

    func test_display_error_carriesMessageAndUnnamedHost() {
        let vm = makeViewModel()
        let server = Server(user: "u", host: "h") // name == nil → host
        vm.addServer(server)
        let fw = Forwarding(serverId: server.id, remotePort: 9000, localPort: 9000, state: .error("boom"))
        let d = vm.display(for: fw)
        XCTAssertEqual(d.status, .error)
        XCTAssertEqual(d.errorMessage, "boom")
        XCTAssertEqual(d.host, "h")
        XCTAssertNil(d.localPort)
    }

    func test_display_starting_noArrow() {
        let vm = makeViewModel()
        let server = Server(user: "u", host: "h")
        vm.addServer(server)
        let fw = Forwarding(serverId: server.id, remotePort: 22, localPort: 22, state: .starting)
        let d = vm.display(for: fw)
        XCTAssertEqual(d.status, .starting)
        XCTAssertNil(d.localPort)
        XCTAssertEqual(d.suffix, ":22")
    }
}
