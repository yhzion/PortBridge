import Foundation
@testable import PortBridge

@MainActor
final class MockTunnelManager: TunnelManaging {
    weak var delegate: TunnelManagerDelegate?

    var nextResult: Forwarding!
    var nextError: Error?
    private(set) var startCalls: [(serverId: UUID, remotePort: Int, localPort: Int)] = []
    private(set) var stopCalls: [UUID] = []
    private(set) var shutdownAllCalled = false

    /// When true, `start` suspends until `resumeStart()` is called.
    /// Used to drive the placeholder-removed-mid-start cancellation path.
    var shouldSuspendStart = false
    private var suspendContinuation: CheckedContinuation<Void, Never>?

    func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding {
        startCalls.append((server.id, remotePort, localPort))
        if shouldSuspendStart {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                suspendContinuation = cont
            }
        }
        if let nextError { throw nextError }
        return nextResult
    }

    func resumeStart() {
        suspendContinuation?.resume()
        suspendContinuation = nil
    }

    func stop(_ id: UUID) {
        stopCalls.append(id)
    }

    func shutdownAll() {
        shutdownAllCalled = true
    }
}
