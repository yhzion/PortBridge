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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel

    override init() {
        // Reap any ssh port-forward processes left orphaned by a previous run
        // (force-quit, crash, Xcode stop) before constructing the view model.
        // applicationWillTerminate is best-effort and won't fire on abnormal exits,
        // so we treat startup cleanup as the authoritative source of correctness.
        TunnelManager.cleanupOrphanedTunnels()
        self.viewModel = AppViewModel()
        super.init()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel.shutdownAll()
        }
    }
}
