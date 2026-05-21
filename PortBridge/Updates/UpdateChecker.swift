import Foundation
import Observation
import os.log

@MainActor
@Observable
final class UpdateChecker {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(ReleaseInfo)
        case failed(checkedAt: Date)
    }

    var phase: Phase = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var skippedVersion: SemanticVersion?
    private(set) var lastNotifiedVersion: SemanticVersion?

    @ObservationIgnored private let fetcher: ReleaseFetcher
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let currentVersion: SemanticVersion?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let log = Logger(subsystem: "PortBridge", category: "UpdateChecker")

    private enum Keys {
        static let lastCheckedAt = "PortBridge.UpdateCheck.LastCheckedAt"
        static let skippedVersion = "PortBridge.UpdateCheck.SkippedVersion"
        static let lastNotifiedVersion = "PortBridge.UpdateCheck.LastNotifiedVersion"
    }

    var availableUpdate: ReleaseInfo? {
        if case .available(let info) = phase { return info }
        return nil
    }

    init(fetcher: ReleaseFetcher,
         defaults: UserDefaults,
         preferences: AppPreferences,
         currentVersion: SemanticVersion?,
         now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.now = now
        self.lastCheckedAt = defaults.object(forKey: Keys.lastCheckedAt) as? Date
        self.skippedVersion = defaults.string(forKey: Keys.skippedVersion)
            .flatMap(SemanticVersion.init(string:))
        self.lastNotifiedVersion = defaults.string(forKey: Keys.lastNotifiedVersion)
            .flatMap(SemanticVersion.init(string:))
    }

    func checkIfDue() async {
        guard preferences.automaticUpdateCheckEnabled else { return }
        if let last = lastCheckedAt, now().timeIntervalSince(last) < 86_400 { return }
        await checkNow()
    }

    func checkNow() async {
        phase = .checking
        do {
            let info = try await fetcher.fetchLatest()
            let timestamp = now()
            lastCheckedAt = timestamp
            defaults.set(timestamp, forKey: Keys.lastCheckedAt)

            guard let current = currentVersion, let remote = info.version else {
                log.warning("Skipping comparison — currentVersion or remote.version nil")
                phase = .upToDate(checkedAt: timestamp)
                return
            }
            let isNewer = remote > current
            let isSkipped = (skippedVersion == remote)
            if isNewer && !isSkipped {
                phase = .available(info)
            } else {
                phase = .upToDate(checkedAt: timestamp)
            }
        } catch {
            log.error("Update check failed: \(String(describing: error), privacy: .public)")
            phase = .failed(checkedAt: now())
        }
    }

    func skipCurrent() {
        guard case .available(let info) = phase, let v = info.version else { return }
        skippedVersion = v
        defaults.set(v.string, forKey: Keys.skippedVersion)
        phase = .upToDate(checkedAt: now())
    }
}
