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
        alert.messageText = String(localized: "update.upToDate.title", defaultValue: "PortBridge가 최신 버전입니다")
        alert.informativeText = String(
            localized: "update.upToDate.message",
            defaultValue: "현재 최신 버전(\(version))을 사용 중입니다."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "update.ok", defaultValue: "확인"))
        runModal(alert)
    }

    func presentFailed(reason: String) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.failed.title", defaultValue: "업데이트를 확인할 수 없습니다")
        alert.informativeText = reason
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update.ok", defaultValue: "확인"))
        runModal(alert)
    }

    func presentAvailable(release: ReleaseInfo) async -> AvailableUserChoice {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "update.available.title",
            defaultValue: "PortBridge \(release.tagName) 업데이트가 있습니다"
        )
        alert.informativeText = informativeText(for: release)
        alert.alertStyle = .informational
        // Order matters — first button is the default (return key).
        alert.addButton(withTitle: String(localized: "update.available.download", defaultValue: "다운로드"))
        alert.addButton(withTitle: String(localized: "update.available.remindLater", defaultValue: "나중에 알림"))
        alert.addButton(withTitle: String(localized: "update.available.skip", defaultValue: "이 버전 건너뛰기"))

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
        AppActivation.runModal(alert)
    }

    private func informativeText(for release: ReleaseInfo) -> String {
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if notes.isEmpty {
            return String(
                localized: "update.available.fallbackMessage",
                defaultValue: "새 버전이 있습니다. 다운로드를 누르면 릴리스 페이지가 열립니다."
            )
        }
        let limit = 600
        if notes.count > limit {
            return String(notes.prefix(limit)) + "…"
        }
        return notes
    }
}
