import Foundation
@testable import PortBridge

final class MockReleaseFetcher: ReleaseFetcher, @unchecked Sendable {
    var result: Result<ReleaseInfo, Error>
    private(set) var callCount = 0

    init(result: Result<ReleaseInfo, Error>) {
        self.result = result
    }

    func fetchLatest() async throws -> ReleaseInfo {
        callCount += 1
        return try result.get()
    }
}
