import XCTest
@testable import PortBridge

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_defaultValues_showInDockTrue_launchAtLoginFalse() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertTrue(prefs.showInDock)
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func test_showInDock_set_callsApplyAndPersists() {
        var captured: [Bool] = []
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { captured.append($0) },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        prefs.showInDock = false
        XCTAssertEqual(captured, [false])
        XCTAssertFalse(defaults.bool(forKey: "PortBridge.ShowInDock"))

        let prefs2 = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertFalse(prefs2.showInDock)
    }

    func test_launchAtLogin_set_true_callsRegisterAndPersists() {
        var capturedDesired: [Bool] = []
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { desired in
                capturedDesired.append(desired)
                return true
            },
            readLaunchAtLogin: { false }
        )
        prefs.launchAtLogin = true
        XCTAssertEqual(capturedDesired, [true])
        XCTAssertTrue(prefs.launchAtLogin)
    }

    func test_launchAtLogin_set_applyFails_keepsPreviousState() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in false },
            readLaunchAtLogin: { false }
        )
        prefs.launchAtLogin = true
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func test_launchAtLogin_initialState_syncsWithSystem() {
        defaults.set(true, forKey: "PortBridge.LaunchAtLogin")
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertFalse(prefs.launchAtLogin)
    }
}
