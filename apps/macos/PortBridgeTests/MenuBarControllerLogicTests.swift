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

    // MARK: - menuTitle (캐노니컬 메뉴 문자열)

    func test_menuTitle_activeWithProcess() {
        let d = ForwardingDisplay.active(host: "myserver (1.2.3.4)", remotePort: 8080, localPort: 3000, processName: "nginx")
        XCTAssertEqual(MenuBarController.menuTitle(for: d), "● myserver (1.2.3.4):8080 → :3000 · nginx")
    }

    func test_menuTitle_inactiveHollow() {
        let d = ForwardingDisplay.inactive(host: "h", remotePort: 5432, processName: nil)
        XCTAssertEqual(MenuBarController.menuTitle(for: d), "○ h:5432")
    }

    // MARK: - batchToggleTitle (일괄 토글 메뉴 항목)

    // toggleAll()의 실제 동작과 문구가 일치해야 한다:
    // 활성 터널이 하나라도 있으면 전부(즐겨찾기 외 포함) 해제, 없으면 즐겨찾기만 연결.

    func test_batchToggleTitle_anyActive_turnsOffAllForwardings() {
        XCTAssertEqual(
            MenuBarController.batchToggleTitle(activeCount: 3, favoriteCount: 5),
            "모든 포워딩 끄기 (3개 활성)"
        )
    }

    func test_batchToggleTitle_noneActive_connectsFavorites() {
        XCTAssertEqual(
            MenuBarController.batchToggleTitle(activeCount: 0, favoriteCount: 5),
            "즐겨찾기 모두 연결 (5개)"
        )
    }

    // MARK: - updateAvailableTitle (업데이트 퍼널 메뉴 항목)

    func test_updateAvailableTitle_includesTagAndDownloadAction() {
        XCTAssertEqual(
            MenuBarController.updateAvailableTitle(tagName: "v0.5.0"),
            "PortBridge v0.5.0 사용 가능 — 다운로드…"
        )
    }
}
