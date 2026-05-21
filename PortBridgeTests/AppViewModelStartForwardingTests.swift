@testable import PortBridge
import XCTest

@MainActor
final class AppViewModelStartForwardingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppViewModelStartForwardingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Test 1: placeholder→tunnel swap must ferry activatedAt

    func test_startForwarding_preservesActivatedAt_acrossPlaceholderSwap() async {
        let store = ServerStore(defaults: defaults)
        let server = Server(name: "test", user: "u", host: "h.example", port: 22)
        store.add(server)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        // Mock returns a Forwarding with a DIFFERENT UUID and nil activatedAt.
        // The production code must ferry the placeholder's activatedAt onto this.
        let tunnelReturned = Forwarding(
            serverId: server.id,
            remotePort: 8080,
            localPort: 8080,
            state: .active,
            activatedAt: nil
        )
        mock.nextResult = tunnelReturned
        let port = RemotePort(port: 8080, address: "0.0.0.0", processName: nil)

        let before = Date()
        await vm.toggleForwarding(serverId: server.id, for: port)
        let after = Date()

        XCTAssertEqual(vm.forwardings.count, 1)
        let final = try? XCTUnwrap(vm.forwardings.first)
        XCTAssertEqual(final?.id, tunnelReturned.id, "should swap to tunnel-returned id")
        // Crucial: activatedAt must have been ferried from the placeholder, not left nil.
        let activatedAt = try? XCTUnwrap(final?.activatedAt)
        XCTAssertNotNil(activatedAt, "activatedAt must be ferried from placeholder")
        if let activatedAt {
            XCTAssertGreaterThanOrEqual(activatedAt, before)
            XCTAssertLessThanOrEqual(activatedAt, after)
        }
    }

    // MARK: - Test 2: activeForwardings sorted newest-first by activatedAt

    func test_activeForwardings_sortedByActivatedAt_newestFirst() async {
        let store = ServerStore(defaults: defaults)
        let server = Server(name: "test", user: "u", host: "h.example", port: 22)
        store.add(server)
        let mock = MockTunnelManager()
        let vm = AppViewModel(store: store, tunnels: mock)

        // First forwarding: older
        let firstFw = Forwarding(serverId: server.id, remotePort: 8080, localPort: 8080, state: .active)
        mock.nextResult = firstFw
        await vm.toggleForwarding(
            serverId: server.id,
            for: RemotePort(port: 8080, address: "0.0.0.0", processName: nil)
        )

        // Force a measurable time gap (>1ms keeps Date comparisons reliable).
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Second forwarding: newer
        let secondFw = Forwarding(serverId: server.id, remotePort: 9090, localPort: 9090, state: .active)
        mock.nextResult = secondFw
        await vm.toggleForwarding(
            serverId: server.id,
            for: RemotePort(port: 9090, address: "0.0.0.0", processName: nil)
        )

        let active = vm.activeForwardings
        XCTAssertEqual(active.count, 2)
        XCTAssertEqual(active.first?.id, secondFw.id, "newest should be first")
        XCTAssertEqual(active.last?.id, firstFw.id, "oldest should be last")
    }

    // MARK: - Test 3: cancellation mid-start triggers tunnel cleanup

    func test_startForwarding_cancellationPath_stopsOrphanedTunnel() async {
        let store = ServerStore(defaults: defaults)
        let server = Server(name: "test", user: "u", host: "h.example", port: 22)
        store.add(server)
        let mock = MockTunnelManager()
        mock.shouldSuspendStart = true
        let returned = Forwarding(serverId: server.id, remotePort: 8080, localPort: 8080, state: .active)
        mock.nextResult = returned
        let vm = AppViewModel(store: store, tunnels: mock)

        let task = Task { @MainActor in
            await vm.toggleForwarding(
                serverId: server.id,
                for: RemotePort(port: 8080, address: "0.0.0.0", processName: nil)
            )
        }

        // Wait until placeholder appears (mock has suspended).
        while vm.forwardings.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(vm.forwardings.count, 1, "placeholder should be present")

        // Simulate user cancellation: remove placeholder while start() is in flight.
        vm.stopAll(for: server.id)
        XCTAssertTrue(vm.forwardings.isEmpty)

        // Resume mock; AppViewModel.startForwarding should detect placeholder gone
        // and call tunnels.stop(returned.id) to avoid leaking the tunnel.
        mock.resumeStart()
        await task.value

        XCTAssertTrue(
            mock.stopCalls.contains(returned.id),
            "expected mock.stop to be called for orphaned tunnel; stopCalls=\(mock.stopCalls)"
        )
        XCTAssertTrue(vm.forwardings.isEmpty, "no forwarding should leak")
    }
}
