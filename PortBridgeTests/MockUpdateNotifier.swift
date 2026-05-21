import Foundation
@testable import PortBridge

@MainActor
final class MockUpdateNotifier: UpdateNotifying {
    private(set) var notifyCalls: [ReleaseInfo] = []
    private(set) var upToDateCalls: [String] = []
    private(set) var failedCalls: [String] = []

    func notify(release: ReleaseInfo) async {
        notifyCalls.append(release)
    }

    func notifyUpToDate(version: String) async {
        upToDateCalls.append(version)
    }

    func notifyFailed(reason: String) async {
        failedCalls.append(reason)
    }
}
