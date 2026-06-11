import AppKit
import Foundation
import os.log

enum AvailableUserChoice {
    case download
    case skip
    case remindLater
}

@MainActor
protocol UpdatePresenting: Sendable {
    func presentUpToDate(version: String) async
    func presentFailed(reason: String) async
    func presentAvailable(release: ReleaseInfo) async -> AvailableUserChoice
}

/// Sparkle-style update dialog using NSAlert.
///
/// `runModal()` blocks the main thread until the user chooses a button — this is the
/// intended UX for an explicit check ("user clicked Check Now and is waiting for an
/// answer"). For automatic checks the alert appears only on the .idle/.upToDate →
/// .available transition, so it does not interrupt continued work.
@MainActor
struct UpdatePresenter: UpdatePresenting {
    private let log = Logger(subsystem: "PortBridge", category: "UpdatePresenter")

    func presentUpToDate(version: String) async {
        let alert = NSAlert()
        alert.messageText = L10n.Updates.upToDateTitle
        alert.informativeText = L10n.Updates.upToDateMessage(version: version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.Updates.ok)
        runModal(alert)
    }

    func presentFailed(reason: String) async {
        let alert = NSAlert()
        alert.messageText = L10n.Updates.checkFailedTitle
        alert.informativeText = reason
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.Updates.ok)
        runModal(alert)
    }

    func presentAvailable(release: ReleaseInfo) async -> AvailableUserChoice {
        let alert = NSAlert()
        alert.messageText = L10n.Updates.availableTitle(tagName: release.tagName)
        alert.informativeText = informativeText(for: release)
        alert.alertStyle = .informational
        // Order matters — first button is the default (return key).
        alert.addButton(withTitle: L10n.Updates.download)
        alert.addButton(withTitle: L10n.Updates.remindLater)
        alert.addButton(withTitle: L10n.Updates.skipThisVersion)

        let response = runModal(alert)
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
            return .download
        case .alertThirdButtonReturn:
            return .skip
        default:
            return .remindLater
        }
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func informativeText(for release: ReleaseInfo) -> String {
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if notes.isEmpty {
            return L10n.Updates.availableFallbackMessage
        }
        let limit = 600
        if notes.count > limit {
            return String(notes.prefix(limit)) + "…"
        }
        return notes
    }
}
