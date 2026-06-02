@testable import PortBridge
import XCTest

@MainActor
final class TunnelManagerArgumentsTests: XCTestCase {
    func test_tunnelArguments_includeConnectTimeout_matchingCore() {
        // The Swift tunnel must mirror the Rust core's ssh args (crates/portbridge-core/
        // src/tunnel.rs). A missing ConnectTimeout made unreachable hosts hang in TCP
        // connect past the 2s start grace → a fake `.active` shown as connected.
        let args = TunnelManager.tunnelArguments(
            serverPort: 22,
            localPort: 5432,
            remotePort: 5432,
            sshTarget: "ubuntu@10.0.0.1"
        )
        XCTAssertEqual(args, [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-p", "22",
            "-L", "5432:localhost:5432",
            "ubuntu@10.0.0.1"
        ])
    }

    func test_tunnelArguments_preserveOrphanCleanupPrefix() {
        // cleanupOrphanedTunnels() pgrep-matches this exact argv prefix. ConnectTimeout
        // must stay AFTER BatchMode=yes so the prefix still matches old and new tunnels.
        let args = TunnelManager.tunnelArguments(
            serverPort: 2222,
            localPort: 8080,
            remotePort: 80,
            sshTarget: "root@example.com"
        )
        let prefix = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes"
        ]
        XCTAssertEqual(Array(args.prefix(prefix.count)), prefix)
    }
}
