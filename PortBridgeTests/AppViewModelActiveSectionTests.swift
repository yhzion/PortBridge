import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelActiveSectionTests: XCTestCase {
    private func makeVM() -> AppViewModel {
        let vm = AppViewModel(parser: { [] })
        vm.selectedHost = SSHHost(name: "prod")
        return vm
    }

    private func remotePort(_ port: Int) -> RemotePort {
        RemotePort(port: port, address: "0.0.0.0", processName: "p\(port)")
    }

    func test_activeForwardedPorts_includesStartingActiveAndError() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .starting),
            Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active),
            Forwarding(host: "prod", remotePort: 22, localPort: 22, state: .error("nope"))
        ]
        let active = vm.activeForwardedPorts
        XCTAssertEqual(Set(active.map { $0.port.port }), [8080, 5432, 22])
    }

    func test_activeForwardedPorts_sortsByActivatedAtDesc() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432)]
        let firstID = UUID()
        let secondID = UUID()
        vm.forwardings = [
            Forwarding(id: firstID, host: "prod", remotePort: 8080, localPort: 8080, state: .active),
            Forwarding(id: secondID, host: "prod", remotePort: 5432, localPort: 5432, state: .active)
        ]
        vm.setActivatedAtForTesting(firstID, Date(timeIntervalSince1970: 100))
        vm.setActivatedAtForTesting(secondID, Date(timeIntervalSince1970: 200))

        let active = vm.activeForwardedPorts
        XCTAssertEqual(active.map { $0.port.port }, [5432, 8080], "최근 활성화가 위")
    }

    func test_inactivePorts_excludesActivePortNumbers() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active)
        ]
        let inactive = vm.inactivePorts
        XCTAssertEqual(Set(inactive.map { $0.port }), [5432, 22])
    }

    func test_inactivePorts_appliesSearchFilter() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
        vm.forwardings = []
        vm.searchText = "80"
        let inactive = vm.inactivePorts
        XCTAssertEqual(inactive.map { $0.port }, [8080])
    }

    func test_activeForwardedPorts_ignoresSearchFilter() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432)]
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active)
        ]
        vm.searchText = "999"
        XCTAssertEqual(vm.activeForwardedPorts.map { $0.port.port }, [5432])
    }

    func test_activeForwardedPorts_emptyWhenHostMismatches() {
        let vm = makeVM()
        vm.selectedHost = SSHHost(name: "other")
        vm.ports = [remotePort(8080)]
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active)
        ]
        XCTAssertTrue(vm.activeForwardedPorts.isEmpty)
    }

    func test_stopAllForCurrentHost_clearsOnlyCurrentHostForwardings() {
        let vm = makeVM()  // selectedHost = "prod"
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active),
            Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active),
            Forwarding(host: "other", remotePort: 22, localPort: 22, state: .active)
        ]
        vm.stopAllForCurrentHost()
        XCTAssertEqual(vm.forwardings.count, 1)
        XCTAssertEqual(vm.forwardings.first?.host, "other")
    }

    func test_stopAllForCurrentHost_clearsActivatedAtForRemovedIDs() {
        let vm = makeVM()
        let id1 = UUID()
        let id2 = UUID()
        vm.forwardings = [
            Forwarding(id: id1, host: "prod", remotePort: 8080, localPort: 8080, state: .active),
            Forwarding(id: id2, host: "other", remotePort: 22, localPort: 22, state: .active)
        ]
        vm.setActivatedAtForTesting(id1, Date())
        vm.setActivatedAtForTesting(id2, Date())

        vm.stopAllForCurrentHost()
        XCTAssertNil(vm.activatedAt[id1])
        XCTAssertNotNil(vm.activatedAt[id2])
    }

    func test_toggleForwardingOff_removesActivatedAtEntry() async {
        let vm = makeVM()
        let port = remotePort(8080)
        let fwID = UUID()
        vm.ports = [port]
        vm.forwardings = [
            Forwarding(id: fwID, host: "prod", remotePort: 8080, localPort: 8080, state: .active)
        ]
        vm.setActivatedAtForTesting(fwID, Date())

        await vm.toggleForwarding(for: port)

        XCTAssertNil(vm.activatedAt[fwID])
        XCTAssertTrue(vm.forwardings.isEmpty)
    }
}
