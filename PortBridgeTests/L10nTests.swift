@testable import PortBridge
import XCTest

final class L10nTests: XCTestCase {
    func test_errorCount_formatsKoreanCount() {
        XCTAssertEqual(L10n.MenuBar.errorCount(1), "오류 1개")
        XCTAssertEqual(L10n.MenuBar.errorCount(3), "오류 3개")
    }

    func test_batchToggleTitle_turnsOffWhenAnyActive() {
        XCTAssertEqual(
            L10n.MenuBar.batchToggleTitle(activeCount: 2, total: 5),
            "모든 즐겨찾기 끄기 (2개 활성)"
        )
    }

    func test_batchToggleTitle_turnsOnWhenNoneActive() {
        XCTAssertEqual(
            L10n.MenuBar.batchToggleTitle(activeCount: 0, total: 5),
            "모든 즐겨찾기 켜기 (5개)"
        )
    }
}
