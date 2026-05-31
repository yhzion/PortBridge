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

    @ObservationIgnored private let fetcher: ReleaseFetcher
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let currentVersion: SemanticVersion?
    @ObservationIgnored private let presenter: UpdatePresenting?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let log = Logger(subsystem: "PortBridge", category: "UpdateChecker")

    private enum Keys {
        static let lastCheckedAt = "PortBridge.UpdateCheck.LastCheckedAt"
        static let skippedVersion = "PortBridge.UpdateCheck.SkippedVersion"
    }

    var availableUpdate: ReleaseInfo? {
        if case .available(let info) = phase { return info }
        return nil
    }

    init(
        fetcher: ReleaseFetcher,
        defaults: UserDefaults,
        preferences: AppPreferences,
        currentVersion: SemanticVersion?,
        presenter: UpdatePresenting? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.presenter = presenter
        self.now = now
        lastCheckedAt = defaults.object(forKey: Keys.lastCheckedAt) as? Date
        skippedVersion = defaults.string(forKey: Keys.skippedVersion)
            .flatMap(SemanticVersion.init(string:))
    }

    func checkIfDue() async {
        guard preferences.automaticUpdateCheckEnabled else { return }
        if let last = lastCheckedAt, now().timeIntervalSince(last) < 86_400 { return }
        await checkNow()
    }

    func checkNow(manual: Bool = false) async {
        log.info("checkNow invoked (manual: \(manual, privacy: .public))")
        let oldPhase = phase
        phase = .checking
        do {
            let info = try await fetcher.fetchLatest()
            let timestamp = now()
            lastCheckedAt = timestamp
            defaults.set(timestamp, forKey: Keys.lastCheckedAt)

            guard let current = currentVersion, let remote = info.version else {
                log.warning("Skipping comparison — currentVersion or remote.version nil")
                phase = .upToDate(checkedAt: timestamp)
                if manual {
                    await presenter?.presentUpToDate(version: currentVersion?.string ?? "unknown")
                }
                return
            }
            // Version verdict runs in core via the `updateAvailable` FFI (single
            // source of truth for parse + compare). `remote` (core-parsed above)
            // is retained for skip-version identity, which is value equality.
            let isNewer = updateAvailable(current: current.ffiDto, latest: info.ffiDto)
            let isSkipped = (skippedVersion == remote)
            if isNewer && !isSkipped {
                phase = .available(info)
                let alreadyShowedSameVersion: Bool = {
                    if case .available(let prev) = oldPhase, prev.version == info.version {
                        return true
                    }
                    return false
                }()
                if manual || !alreadyShowedSameVersion {
                    await handleAvailable(info)
                }
            } else {
                phase = .upToDate(checkedAt: timestamp)
                if manual {
                    await presenter?.presentUpToDate(version: current.string)
                }
            }
        } catch {
            log.error("Update check failed: \(String(describing: error), privacy: .public)")
            phase = .failed(checkedAt: now())
            if manual {
                await presenter?.presentFailed(reason: humanReadable(error))
            }
        }
    }

    func skipCurrent() {
        guard case .available(let info) = phase, let v = info.version else { return }
        skippedVersion = v
        defaults.set(v.string, forKey: Keys.skippedVersion)
        phase = .upToDate(checkedAt: now())
    }

    private func handleAvailable(_ info: ReleaseInfo) async {
        guard let presenter else { return }
        let choice = await presenter.presentAvailable(release: info)
        if choice == .skip {
            skipCurrent()
        }
    }

    private func humanReadable(_ error: Error) -> String {
        guard let updateError = error as? UpdateCheckError else {
            return "Unexpected error: \(error.localizedDescription)"
        }
        switch updateError {
        case .network: return "Network unavailable. Check your connection."
        case .httpStatus(404): return "No releases found on GitHub yet."
        case .httpStatus(403): return "GitHub rate limit reached. Try again in an hour."
        case .httpStatus(let code): return "Server returned HTTP \(code)."
        case .invalidResponse: return "Unexpected response from GitHub."
        case .decoding: return "Couldn't parse the release information."
        }
    }
}
