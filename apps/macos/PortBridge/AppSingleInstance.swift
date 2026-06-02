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

    /// 기존 인스턴스 재활성화 요청 시 호출할 콜백. AppDelegate가 주입한다.
    /// `NSApp.delegate as? AppDelegate` 캐스트는 Debug dylib 분리 등으로 타입 정체성이
    /// 어긋나 nil이 될 수 있어(메뉴 "Open Main Window"가 안 되던 원인) 사용하지 않는다.
    @MainActor static var onActivateRequested: (() -> Void)?

    static func activateCurrentInstance() {
        MainActor.assumeIsolated {
            onActivateRequested?()
        }
    }

    private static func requestExistingInstanceActivation() {
        DistributedNotificationCenter.default().post(
            name: activationNotification,
            object: nil,
            userInfo: nil
        )
    }
}
