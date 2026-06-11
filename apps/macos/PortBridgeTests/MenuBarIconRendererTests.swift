@testable import PortBridge
import XCTest

final class MenuBarIconRendererTests: XCTestCase {
    // MARK: - accessibilityDescription (active × badged)

    func test_accessibilityDescription_idle() {
        XCTAssertEqual(
            MenuBarIconRenderer.accessibilityDescription(active: false, badged: false),
            "PortBridge — 대기 중"
        )
    }

    func test_accessibilityDescription_active() {
        XCTAssertEqual(
            MenuBarIconRenderer.accessibilityDescription(active: true, badged: false),
            "PortBridge — 포워딩 활성"
        )
    }

    func test_accessibilityDescription_idleWithUpdate() {
        XCTAssertEqual(
            MenuBarIconRenderer.accessibilityDescription(active: false, badged: true),
            "PortBridge — 대기 중, 업데이트 있음"
        )
    }

    func test_accessibilityDescription_activeWithUpdate() {
        XCTAssertEqual(
            MenuBarIconRenderer.accessibilityDescription(active: true, badged: true),
            "PortBridge — 포워딩 활성, 업데이트 있음"
        )
    }
}
