@testable import PortBridge
import XCTest

final class FavoriteRowDisplayTests: XCTestCase {
    private func row(state: Forwarding.State, isOffline: Bool, localPort: Int? = 3000) -> FavoriteRow {
        FavoriteRow(
            id: FavoriteKey(serverId: UUID(), remotePort: 5432),
            serverDisplayName: "db (10.0.0.1)",
            remotePort: 5432,
            localPort: localPort,
            processName: "postgres",
            state: state,
            isOffline: isOffline,
            isOnlineConfirmed: false
        )
    }

    /// 핵심 회귀: offline 서버의 stale .active는 ● 아닌 ○ (기존 AppViewModelFavoritesTests:152 방어).
    func test_offlineActive_suppressedToInactive() {
        let d = row(state: .active, isOffline: true).display
        XCTAssertEqual(d.status, .inactive)
        XCTAssertEqual(d.statusDot, "○")
        XCTAssertNil(d.localPort)
    }

    func test_onlineActive_isActiveWithArrow() {
        let d = row(state: .active, isOffline: false, localPort: 3000).display
        XCTAssertEqual(d.status, .active)
        XCTAssertEqual(d.statusDot, "●")
        XCTAssertEqual(d.line, "db (10.0.0.1):5432 → :3000 · postgres")
    }

    func test_onlineStarting_filledDot_noArrow() {
        let d = row(state: .starting, isOffline: false).display
        XCTAssertEqual(d.status, .starting)
        XCTAssertEqual(d.statusDot, "●")
        XCTAssertEqual(d.suffix, ":5432 · postgres")
    }

    func test_onlineError_hollowDot() {
        let d = row(state: .error("x"), isOffline: false).display
        XCTAssertEqual(d.status, .error)
        XCTAssertEqual(d.statusDot, "○")
    }

    func test_onlineIdle_inactive() {
        let d = row(state: .idle, isOffline: false).display
        XCTAssertEqual(d.status, .inactive)
    }
}
