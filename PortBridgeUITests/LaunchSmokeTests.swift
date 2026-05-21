import XCTest

/// PortBridge는 메뉴바(MenuBarExtra) 우선 디자인이라
/// launch 직후 메인 윈도우가 자동 표시되지 않는 게 정상이다.
/// 따라서 smoke 검증과 윈도우 검증을 두 테스트로 분리한다.
final class LaunchSmokeTests: XCTestCase {

    /// 앱이 크래시 없이 launch되는지만 검증한다.
    /// 메인 윈도우/메뉴바 표시 여부는 무관 — 이 테스트의 가치는
    /// "AppDelegate.init / applicationDidFinishLaunching 경로의 즉시 회귀"를 잡는 것.
    @MainActor
    func test_app_launches() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()

        // init/applicationDidFinishLaunching 시퀀스가 끝날 시간을 짧게 준 뒤,
        // 즉시 죽지 않았는지 확인한다. 메뉴바 전용 모드여도 .runningBackground는 정상.
        Thread.sleep(forTimeInterval: 1.5)

        let aliveStates: Set<XCUIApplication.State> = [.runningForeground, .runningBackground]
        XCTAssertTrue(aliveStates.contains(app.state),
                      "App terminated or entered unexpected state during launch (state=\(app.state.rawValue))")
    }

    /// 사용자가 메인 윈도우 표시를 요청했을 때 윈도우가 나타나는지 검증한다.
    /// -OpenMainWindowOnLaunch flag를 AppDelegate가 감지해 명시적으로 활성화한다
    /// (PortBridgeApp.swift의 applicationDidFinishLaunching 참고).
    @MainActor
    func test_mainWindow_opensOnCommand() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-OpenMainWindowOnLaunch"]
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5),
                      "Main window did not appear within 5s after -OpenMainWindowOnLaunch")
    }
}
