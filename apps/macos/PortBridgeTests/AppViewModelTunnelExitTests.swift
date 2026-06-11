@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelTunnelExitTests: XCTestCase {
    private final class MockNotifier: UserNotifying {
        private(set) var posts: [(title: String, body: String)] = []
        func post(title: String, body: String) {
            posts.append((title, body))
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AVMTunnelExit.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeViewModel(notifier: UserNotifying) -> AppViewModel {
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
            ),
            notifier: notifier
        )
    }

    func test_tunnelDidExit_unexpectedDeath_setsErrorAndNotifies() async {
        let notifier = MockNotifier()
        let vm = makeViewModel(notifier: notifier)
        let server = Server(name: "db", user: "u", host: "10.0.0.1")
        vm.addServer(server)
        vm._test_injectActiveForwarding(serverId: server.id, remotePort: 5432)
        let fw = vm.activeForwardings[0]

        await vm.tunnelDidExit(id: fw.id, stderr: "Connection refused")

        guard case .error = vm.forwardings.first?.state else {
            XCTFail("expected .error state"); return
        }
        XCTAssertEqual(notifier.posts.count, 1)
        XCTAssertEqual(notifier.posts.first?.title, "포워딩이 중단되었습니다")
        XCTAssertTrue(notifier.posts.first?.body.contains(":5432") ?? false)
        XCTAssertTrue(notifier.posts.first?.body.contains("연결이 거부되었습니다") ?? false)
    }

    func test_tunnelDidExit_unknownId_doesNotNotify() async {
        // 수동 stop 경로는 toggleForwarding이 목록에서 먼저 제거하므로
        // exit 콜백 시점엔 id가 없다 — 예기치 못한 사망만 알림이 가야 한다.
        let notifier = MockNotifier()
        let vm = makeViewModel(notifier: notifier)

        await vm.tunnelDidExit(id: UUID(), stderr: "exited")

        XCTAssertTrue(notifier.posts.isEmpty)
    }
}
