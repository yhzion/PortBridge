import XCTest
@testable import PortBridge

final class AppInstanceLockTests: XCTestCase {
    private var lockURL: URL!

    override func setUpWithError() throws {
        lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortBridgeTests-\(UUID().uuidString).lock")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: lockURL)
        lockURL = nil
    }

    func test_lockPreventsSecondOwnerUntilReleased() {
        let first = AppInstanceLock(lockFileURL: lockURL)
        let second = AppInstanceLock(lockFileURL: lockURL)

        XCTAssertTrue(first.acquire())
        XCTAssertFalse(second.acquire())

        first.release()

        XCTAssertTrue(second.acquire())
        second.release()
    }

    func test_releaseIsIdempotent() {
        let lock = AppInstanceLock(lockFileURL: lockURL)

        XCTAssertTrue(lock.acquire())
        lock.release()

        XCTAssertNoThrow(lock.release())
    }
}
