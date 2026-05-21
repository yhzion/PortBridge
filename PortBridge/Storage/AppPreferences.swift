import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppPreferences {
    private let defaults: UserDefaults
    private let applyShowInDock: (Bool) -> Void
    private let applyLaunchAtLogin: (Bool) -> Bool

    private let showInDockKey = "PortBridge.ShowInDock"
    private let launchAtLoginKey = "PortBridge.LaunchAtLogin"

    @ObservationIgnored
    private var suppressApply = false

    var showInDock: Bool {
        didSet {
            guard !suppressApply, showInDock != oldValue else { return }
            defaults.set(showInDock, forKey: showInDockKey)
            applyShowInDock(showInDock)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !suppressApply, launchAtLogin != oldValue else { return }
            let succeeded = applyLaunchAtLogin(launchAtLogin)
            if !succeeded {
                suppressApply = true
                launchAtLogin = oldValue
                suppressApply = false
                return
            }
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        applyShowInDock: @escaping (Bool) -> Void,
        applyLaunchAtLogin: @escaping (Bool) -> Bool,
        readLaunchAtLogin: () -> Bool
    ) {
        self.defaults = defaults
        self.applyShowInDock = applyShowInDock
        self.applyLaunchAtLogin = applyLaunchAtLogin

        if defaults.object(forKey: showInDockKey) == nil {
            showInDock = true
        } else {
            showInDock = defaults.bool(forKey: showInDockKey)
        }

        let systemEnabled = readLaunchAtLogin()
        launchAtLogin = systemEnabled
        defaults.set(systemEnabled, forKey: launchAtLoginKey)
    }
}

extension AppPreferences {
    /// Production factory wiring real macOS APIs.
    static func production(defaults: UserDefaults = .standard) -> AppPreferences {
        AppPreferences(
            defaults: defaults,
            applyShowInDock: { show in
                NSApp.setActivationPolicy(show ? .regular : .accessory)
            },
            applyLaunchAtLogin: { desired in
                do {
                    if desired {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    return true
                } catch {
                    return false
                }
            },
            readLaunchAtLogin: {
                SMAppService.mainApp.status == .enabled
            }
        )
    }
}
