import Foundation
@testable import PortBridge

@MainActor
final class MockUpdateNotifier: UpdateNotifying {
    private(set) var notifyCalls: [ReleaseInfo] = []

    func notify(release: ReleaseInfo) async {
        notifyCalls.append(release)
    }
}
