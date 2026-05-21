import SwiftUI
import AppKit

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(delegate.viewModel)
        }
        .commands {
            // ⌘N은 ServerListView에서 "서버 추가"에 사용하므로 기본 "새 창" 바인딩 해제.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel

    override init() {
        if !Self.isRunningUnderTest {
            AppSingleInstance.exitIfAnotherInstanceIsRunning()
            // Reap any ssh port-forward processes left orphaned by a previous run
            // (force-quit, crash, Xcode stop) before constructing the view model.
            // applicationWillTerminate is best-effort and won't fire on abnormal exits,
            // so we treat startup cleanup as the authoritative source of correctness.
            TunnelManager.cleanupOrphanedTunnels()
        }
        self.viewModel = AppViewModel()
        super.init()
        AppSingleInstance.startActivationObserver()
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
}
