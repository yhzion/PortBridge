@testable import PortBridge
import XCTest

@MainActor
final class MenuBarControllerLogicTests: XCTestCase {
    // MARK: - shouldDim truth table

    // Dim only when the server is neither confirmed-online nor trustworthily connected.
    // A live tunnel (isConnected) or a successful scan (isOnlineConfirmed) keeps the row crisp.

    func test_shouldDim_onlineConfirmed_neverDims() {
        XCTAssertFalse(MenuBarController.shouldDim(isOnlineConfirmed: true, isConnected: true))
        XCTAssertFalse(MenuBarController.shouldDim(isOnlineConfirmed: true, isConnected: false))
    }

    func test_shouldDim_unconfirmedButConnected_doesNotDim() {
        // e.g. .idle/.scanning with a live forwarding — trust the tunnel.
        XCTAssertFalse(MenuBarController.shouldDim(isOnlineConfirmed: false, isConnected: true))
    }

    func test_shouldDim_unconfirmedAndNotConnected_dims() {
        // e.g. .idle/.offline/.error with no live tunnel — unconfirmed, so dim.
        XCTAssertTrue(MenuBarController.shouldDim(isOnlineConfirmed: false, isConnected: false))
    }

    // MARK: - shouldScan throttle

    func test_shouldScan_firstOpen_alwaysScans() {
        XCTAssertTrue(MenuBarController.shouldScan(now: Date(), last: nil, throttle: 15))
    }

    func test_shouldScan_withinThrottle_skips() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = Date(timeIntervalSince1970: 990) // 10s ago, throttle 15s
        XCTAssertFalse(MenuBarController.shouldScan(now: now, last: last, throttle: 15))
    }

    func test_shouldScan_pastThrottle_scans() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = Date(timeIntervalSince1970: 980) // 20s ago, throttle 15s
        XCTAssertTrue(MenuBarController.shouldScan(now: now, last: last, throttle: 15))
    }

    func test_shouldScan_exactlyAtThrottle_scans() {
        let now = Date(timeIntervalSince1970: 1000)
        let last = Date(timeIntervalSince1970: 985) // exactly 15s ago
        XCTAssertTrue(MenuBarController.shouldScan(now: now, last: last, throttle: 15))
    }
}
