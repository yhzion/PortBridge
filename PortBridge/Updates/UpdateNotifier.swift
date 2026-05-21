import Foundation
import os.log
import UserNotifications

@MainActor
protocol UpdateNotifying: Sendable {
    func notify(release: ReleaseInfo) async
    func notifyUpToDate(version: String) async
    func notifyFailed(reason: String) async
}

@MainActor
struct UpdateNotifier: UpdateNotifying {
    let center: UNUserNotificationCenter
    private let log = Logger(subsystem: "PortBridge", category: "UpdateNotifier")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func notify(release: ReleaseInfo) async {
        await deliver(
            identifier: "PortBridge.UpdateAvailable.\(release.tagName)",
            title: "PortBridge update available",
            body: "\(release.tagName) is ready to download."
        )
    }

    func notifyUpToDate(version: String) async {
        await deliver(
            identifier: "PortBridge.UpdateCheck.UpToDate",
            title: "PortBridge is up to date",
            body: "You're on the latest version (\(version))."
        )
    }

    func notifyFailed(reason: String) async {
        await deliver(
            identifier: "PortBridge.UpdateCheck.Failed",
            title: "Couldn't check for updates",
            body: reason
        )
    }

    private func deliver(identifier: String, title: String, body: String) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                log.info("Notification permission not granted — skipping banner")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            log.error("Failed to schedule notification: \(String(describing: error), privacy: .public)")
        }
    }
}
