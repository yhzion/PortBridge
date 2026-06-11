@testable import PortBridge
import XCTest

final class ForwardingRowViewTests: XCTestCase {
    func test_statusSymbol_idleHovering_showsPlayAffordance() {
        let symbol = ForwardingRowView.statusSymbol(for: nil, isHovering: true)
        XCTAssertEqual(symbol.name, "play.circle.fill")
    }

    func test_statusSymbol_idleNotHovering_showsCircle() {
        let symbol = ForwardingRowView.statusSymbol(for: .idle, isHovering: false)
        XCTAssertEqual(symbol.name, "circle")
    }

    func test_statusSymbol_activeHovering_keepsActiveSymbol() {
        let symbol = ForwardingRowView.statusSymbol(for: .active, isHovering: true)
        XCTAssertEqual(symbol.name, "circle.fill")
    }

    func test_statusSymbol_errorHovering_keepsWarningSymbol() {
        let symbol = ForwardingRowView.statusSymbol(for: .error("refused"), isHovering: true)
        XCTAssertEqual(symbol.name, "exclamationmark.triangle.fill")
    }
}
