import Foundation
@testable import PortBridge

@MainActor
final class MockUpdatePresenter: UpdatePresenting {
    private(set) var upToDateCalls: [String] = []
    private(set) var failedCalls: [String] = []
    private(set) var availableCalls: [ReleaseInfo] = []

    /// Sequenced responses for `presentAvailable`. Defaults to `.remindLater` once
    /// exhausted so existing tests that don't care about the choice keep working.
    var availableResponses: [AvailableUserChoice] = []

    func presentUpToDate(version: String) async {
        upToDateCalls.append(version)
    }

    func presentFailed(reason: String) async {
        failedCalls.append(reason)
    }

    func presentAvailable(release: ReleaseInfo) async -> AvailableUserChoice {
        availableCalls.append(release)
        if availableResponses.isEmpty { return .remindLater }
        return availableResponses.removeFirst()
    }
}
