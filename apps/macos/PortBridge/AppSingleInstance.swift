import AppKit
import Darwin
import Foundation

final class AppInstanceLock {
    private let lockFileURL: URL
    private var descriptor: Int32 = -1

    init(lockFileURL: URL) {
        self.lockFileURL = lockFileURL
    }

    deinit {
        release()
    }

    func acquire() -> Bool {
        guard descriptor < 0 else { return true }

        let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }

        descriptor = fd
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }

        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}

enum AppSingleInstance {
    private static let activationNotification = NSNotification.Name("youngho.jeon.PortBridge.activate")
    private static let lock = AppInstanceLock(
        lockFileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("youngho.jeon.PortBridge.lock")
    )
    private static var activationObserver: NSObjectProtocol?

    static func exitIfAnotherInstanceIsRunning() {
        guard lock.acquire() else {
            requestExistingInstanceActivation()
            usleep(100_000)
            exit(0)
        }
    }

    static func startActivationObserver() {
        guard activationObserver == nil else { return }

        activationObserver = DistributedNotificationCenter.default().addObserver(
            forName: activationNotification,
            object: nil,
            queue: .main
        ) { _ in
            activateCurrentInstance()
        }
    }

    static func stop() {
        if let activationObserver {
            DistributedNotificationCenter.default().removeObserver(activationObserver)
            self.activationObserver = nil
        }
        lock.release()
    }

    @discardableResult
    static func activateCurrentInstance() -> Bool {
        AppActivation.activate()

        guard let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized })
            ?? NSApp.windows.first
        else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private static func requestExistingInstanceActivation() {
        DistributedNotificationCenter.default().post(
            name: activationNotification,
            object: nil,
            userInfo: nil
        )
    }
}
