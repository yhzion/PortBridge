@testable import PortBridge
import XCTest

@MainActor
final class AppDelegateTerminationTests: XCTestCase {
    func test_shouldConfirmTermination_falseWhenNoActiveForwardings() {
        XCTAssertFalse(AppDelegate.shouldConfirmTermination(activeCount: 0))
    }

    func test_shouldConfirmTermination_trueWhenActiveForwardingsExist() {
        XCTAssertTrue(AppDelegate.shouldConfirmTermination(activeCount: 1))
        XCTAssertTrue(AppDelegate.shouldConfirmTermination(activeCount: 3))
    }
}
