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
    let viewModel = AppViewModel()

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel.shutdownAll()
        }
    }
}
