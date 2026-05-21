import AppKit
import SwiftUI

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            MainContentHost(viewModel: delegate.viewModel)
        }
        .commands {
            // ⌘N은 ServerListView에서 "서버 추가"에 사용하므로 기본 "새 창" 바인딩 해제.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// WindowGroup의 루트. openWindow 환경값을 얻어 메뉴바의 "Open Main Window" 알림에 반응합니다.
private struct MainContentHost: View {
    let viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environment(viewModel)
            .onReceive(NotificationCenter.default.publisher(for: .openPortBridgeMainWindow)) { _ in
                openWindow(id: "main")
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel
    private var menuBarController: MenuBarController?

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
        Task { @MainActor in
            await viewModel.updates.checkIfDue()
        }

        // UI 테스트가 메인 윈도우 표시를 명시 요청한 경우 (LaunchSmokeTests 참조).
        // 액세서리 모드일 수 있어 WindowGroup의 자동 표시가 환경에 따라 불확실하므로,
        // 테스트 결정성을 위해 첫 윈도우를 강제로 전면에 띄운다.
        if Self.shouldOpenMainWindowOnLaunch {
            Task { @MainActor in
                // SwiftUI scene이 WindowGroup 윈도우를 생성할 시간을 짧게 확보.
                try? await Task.sleep(for: .milliseconds(200))
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !AppSingleInstance.activateCurrentInstance()
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
