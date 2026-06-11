@testable import PortBridge
import XCTest

final class ForwardingRowViewTests: XCTestCase {
    // MARK: - statusSymbol (상태 × hover → 심볼)

    // inactive 행은 hover 시 ▶로 바뀌어 "클릭=연결" 어포던스를 제공한다.
    // active/error는 hover와 무관하게 상태 심볼을 유지한다.

    func test_statusSymbol_inactiveHovering_showsPlayAffordance() {
        let symbol = ForwardingRowView.statusSymbol(for: .inactive, isHovering: true)
        XCTAssertEqual(symbol.name, "play.circle.fill")
    }

    func test_statusSymbol_inactiveNotHovering_showsCircle() {
        let symbol = ForwardingRowView.statusSymbol(for: .inactive, isHovering: false)
        XCTAssertEqual(symbol.name, "circle")
    }

    func test_statusSymbol_activeHovering_keepsActiveSymbol() {
        let symbol = ForwardingRowView.statusSymbol(for: .active, isHovering: true)
        XCTAssertEqual(symbol.name, "circle.fill")
    }

    func test_statusSymbol_errorHovering_keepsWarningSymbol() {
        let symbol = ForwardingRowView.statusSymbol(for: .error, isHovering: true)
        XCTAssertEqual(symbol.name, "exclamationmark.triangle.fill")
    }
}
