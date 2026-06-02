import AppKit
import SwiftUI

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // WindowGroup 자체는 SwiftUI App이 자신을 *windowed app*으로 분류하도록 두지만,
        // macOS 26 / SwiftUI 7 + NSApplicationDelegateAdaptor 조합에서는 launch 시 첫
        // 윈도우가 자동 인스턴스화되지 않습니다. 실제 메인 윈도우 표시는
        // AppDelegate.showMainWindow(AppKit NSWindow + NSHostingController)가 맡습니다.
        WindowGroup(id: "main") {
            MainContentHost(viewModel: delegate.viewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct MainContentHost: View {
    let viewModel: AppViewModel

    var body: some View {
        ContentView()
            .environment(viewModel)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let viewModel: AppViewModel
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?

    override init() {
        if !Self.isRunningUnderTest {
            AppSingleInstance.exitIfAnotherInstanceIsRunning()
            // Reap any ssh port-forward processes left orphaned by a previous run
            // (force-quit, crash, Xcode stop) before constructing the view model.
            // applicationWillTerminate is best-effort and won't fire on abnormal exits,
            // so we treat startup cleanup as the authoritative source of correctness.
            TunnelManager.cleanupOrphanedTunnels()
        }
        viewModel = AppViewModel()
        super.init()
        AppSingleInstance.startActivationObserver()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 영속화된 사용자 선택을 깜빡임 없이 즉시 반영
        NSApp.setActivationPolicy(viewModel.preferences.showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 아이콘 + 좌/우클릭 핸들러 설치
        let controller = MenuBarController(viewModel: viewModel)
        controller.install()
        menuBarController = controller

        // 즐겨찾기 자동 시작 — launchAtLogin이 켜져 있을 때만
        Task { @MainActor in
            await viewModel.startFavoritesIfEnabled()
        }

        // Background update check on launch (no-op if disabled or recently checked).
        // Skipped under XCTest: the live GitHubReleaseFetcher network call during the
        // test host's launch stalls runner attachment ("Test runner never began
        // executing tests after launching" — macOS parity CI flakiness). Mirrors the
        // launch-side-effect skips in init().
        if !Self.isRunningUnderTest {
            Task(priority: .utility) { @MainActor in
                await viewModel.updates.checkIfDue()
            }
        }

        if Self.shouldOpenMainWindowOnLaunch {
            showMainWindow()
        }
    }

    /// 메인 윈도우를 표시합니다. 처음 호출 시 AppKit NSWindow를 만들고 ContentView를
    /// NSHostingController로 호스팅하며, 이후 호출은 같은 인스턴스를 재사용합니다.
    ///
    /// macOS 26 / SwiftUI 7에서는 NSApplicationDelegateAdaptor와 함께 사용 시
    /// WindowGroup이 launch 시 자동 윈도우를 만들지 않는 동작을 우회하기 위해
    /// AppKit으로 직접 호스팅합니다. 사용자가 메뉴바를 통해 호출(user gesture)하므로
    /// `NSApp.activate()`가 정상 동작합니다.
    func showMainWindow() {
        if mainWindow == nil {
            let host = NSHostingController(rootView: ContentView().environment(viewModel))
            let window = NSWindow(contentViewController: host)
            window.title = "PortBridge"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 900, height: 600))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            mainWindow = window
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        showMainWindow()
        return false
    }

    // MARK: - NSWindowDelegate

    /// 닫기 버튼을 hide로 치환합니다. NSWindow 객체는 유지되어
    /// 이후 `showMainWindow()` 호출 시 `makeKeyAndOrderFront`가 즉시 동작합니다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel.shutdownAll()
        }
        AppSingleInstance.stop()
    }

    private static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    private static var shouldOpenMainWindowOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-OpenMainWindowOnLaunch")
    }
}
