import XCTest

final class LaunchSmokeTests: XCTestCase {
    @MainActor
    func test_app_launchesAndShowsMainWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5),
                      "Main window did not appear within 5s")
    }
}
