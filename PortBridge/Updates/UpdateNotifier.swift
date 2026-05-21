import Foundation
import UserNotifications
import os.log

@MainActor
protocol UpdateNotifying: Sendable {
    func notify(release: ReleaseInfo) async
}

@MainActor
struct UpdateNotifier: UpdateNotifying {
    let center: UNUserNotificationCenter
    private let log = Logger(subsystem: "PortBridge", category: "UpdateNotifier")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func notify(release: ReleaseInfo) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                log.info("Notification permission not granted — skipping banner")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "PortBridge update available"
            content.body = "\(release.tagName) is ready to download."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "PortBridge.UpdateAvailable.\(release.tagName)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            log.error("Failed to schedule notification: \(String(describing: error), privacy: .public)")
        }
    }
}
