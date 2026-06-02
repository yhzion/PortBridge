import AppKit
import SwiftUI

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 메인 윈도우는 AppDelegate.showMainWindow(AppKit NSWindow + NSHostingController)가
        // 전담한다. WindowGroup은 launch 시 창을 강제 생성해 AppKit 창과 중복되고
        // (.defaultLaunchBehavior(.suppressed)로도 막히지 않음 — 진단으로 확인) 포커스
        // 경쟁을 일으키므로, 자동 창을 만들지 않는 Settings 씬만 둔다.
        Settings {
            EmptyView()
        }
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
        PBDiag.reset("LAUNCH build=DIAG1 args=\(ProcessInfo.processInfo.arguments) policy=\(NSApp.activationPolicy().rawValue)")
        // 메뉴바 아이콘 + 좌/우클릭 핸들러 설치.
        // showMainWindow는 클로저로 직접 주입한다. `NSApp.delegate as? AppDelegate`
        // 캐스트는 Debug dylib 분리 등으로 타입 정체성이 어긋나 nil이 될 수 있어 사용하지 않는다.
        let controller = MenuBarController(viewModel: viewModel) { [weak self] in
            self?.showMainWindow()
        }
        controller.install()
        // 2nd-instance 재활성화도 같은 이유로 캐스트 대신 콜백으로 연결한다.
        AppSingleInstance.onActivateRequested = { [weak self] in self?.showMainWindow() }
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
        PBDiag.dumpWindows("didFinishLaunching")
        RunLoop.current.perform(inModes: [.default]) { PBDiag.dumpWindows("post-launch-runloop") }
    }

    /// 메인 윈도우를 표시합니다. 처음 호출 시 AppKit NSWindow를 만들고 ContentView를
    /// NSHostingController로 호스팅하며, 이후 호출은 같은 인스턴스를 재사용합니다.
    ///
    /// macOS 26 / SwiftUI 7에서는 NSApplicationDelegateAdaptor와 함께 사용 시
    /// WindowGroup이 launch 시 자동 윈도우를 만들지 않는 동작을 우회하기 위해
    /// AppKit으로 직접 호스팅합니다. 사용자가 메뉴바를 통해 호출(user gesture)하므로
    /// `NSApp.activate()`가 정상 동작합니다.
    func showMainWindow() {
        PBDiag.log("showMainWindow ENTER mainWindowNil=\(mainWindow == nil) isActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)")
        PBDiag.dumpWindows("sMW-enter")
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
            PBDiag.log("showMainWindow CREATED window")
        }
        guard let window = mainWindow else { PBDiag.log("showMainWindow GUARD-BAIL"); return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // .accessory 정책에서는 창이 보이는 동안 .regular를 유지해야 합니다.
        // 정책 복원은 windowShouldClose(_:)에서 수행합니다.
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        PBDiag.log("showMainWindow PRE-activate isActive=\(NSApp.isActive)")
        // 상태바 메뉴 클릭은 앱을 활성화하지 않으므로(macOS 14+), 백그라운드 앱에서는
        // cooperative NSApp.activate()가 no-op이 됩니다. deprecated지만 강제로
        // 활성화하는 ignoringOtherApps를 써야 창이 전면+포커스를 받습니다.
        NSApp.activate(ignoringOtherApps: true)
        PBDiag.log("showMainWindow POST-activate isActive=\(NSApp.isActive)")
        // orderFrontRegardless 는 활성화 전파 전에도 창을 보이게 한다.
        // makeKeyAndOrderFront 는 활성화 완료 시 이 창이 key가 되도록 의도를 설정한다
        // (makeKey 단독은 비활성 상태에서 key 지정이 누락될 수 있음).
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        PBDiag.log("showMainWindow DONE isVisible=\(window.isVisible) isKey=\(window.isKeyWindow) onActiveSpace=\(window.isOnActiveSpace) frame=\(NSStringFromRect(window.frame))")
        PBDiag.dumpWindows("sMW-done")
        // 활성화 비동기 전파 후 상태 확인용
        RunLoop.current.perform(inModes: [.default]) { PBDiag.dumpWindows("sMW-post-runloop") }
    }

    /// 메인 윈도우가 현재 화면에 보이는지 여부.
    var isMainWindowVisible: Bool {
        mainWindow?.isVisible == true
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
        // showMainWindow()에서 .regular로 올린 정책을 창 닫힐 때 복원
        if !viewModel.preferences.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }
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
