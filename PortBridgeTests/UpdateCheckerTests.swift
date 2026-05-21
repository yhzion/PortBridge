@testable import PortBridge
import XCTest

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.UpdateCheckerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makePrefs(autoEnabled: Bool = true) -> AppPreferences {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        prefs.automaticUpdateCheckEnabled = autoEnabled
        return prefs
    }

    private func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(
            tagName: tag,
            name: tag,
            htmlURL: URL(string: "https://example.com/\(tag)")!,
            publishedAt: nil,
            body: nil
        )
    }

    func test_checkNow_detectsNewerVersion() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher,
            defaults: defaults,
            preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        XCTAssertEqual(checker.phase, .available(release("v0.2.0")))
    }

    func test_checkNow_sameVersionIsUpToDate() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.1.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        if case .upToDate = checker.phase { } else {
            XCTFail("Expected .upToDate, got \(checker.phase)")
        }
    }

    func test_checkNow_olderRemoteIsUpToDate() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.0.9")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        if case .upToDate = checker.phase { } else {
            XCTFail("Expected .upToDate, got \(checker.phase)")
        }
    }

    func test_skipCurrent_suppressesAvailable() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        checker.skipCurrent()
        if case .upToDate = checker.phase { } else {
            XCTFail("Expected .upToDate after skip")
        }
        XCTAssertEqual(checker.skippedVersion, SemanticVersion(string: "0.2.0"))

        // Subsequent check with same version still skipped
        await checker.checkNow()
        if case .upToDate = checker.phase { } else {
            XCTFail("Skipped version should remain hidden")
        }
    }

    func test_higherThanSkippedShowsAgain() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        checker.skipCurrent()

        // New higher release appears
        fetcher.result = .success(release("v0.3.0"))
        await checker.checkNow()
        XCTAssertEqual(checker.phase, .available(release("v0.3.0")))
    }

    func test_networkErrorYieldsFailed() async {
        let fetcher = MockReleaseFetcher(
            result: .failure(UpdateCheckError.network(URLError(.notConnectedToInternet)))
        )
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        if case .failed = checker.phase { } else {
            XCTFail("Expected .failed, got \(checker.phase)")
        }
    }

    func test_checkIfDue_debouncesWithin24h() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let now = Date()
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            now: { now }
        )
        await checker.checkIfDue()
        XCTAssertEqual(fetcher.callCount, 1)

        // Second call within 24h should not refetch
        await checker.checkIfDue()
        XCTAssertEqual(fetcher.callCount, 1)
    }

    func test_checkIfDue_refetchesAfter24h() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        var current = Date()
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            now: { current }
        )
        await checker.checkIfDue()
        XCTAssertEqual(fetcher.callCount, 1)

        current = current.addingTimeInterval(86_401)
        await checker.checkIfDue()
        XCTAssertEqual(fetcher.callCount, 2)
    }

    func test_checkIfDue_respectsDisabledPreference() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults,
            preferences: makePrefs(autoEnabled: false),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkIfDue()
        XCTAssertEqual(fetcher.callCount, 0)
    }

    func test_checkNow_ignoresDisabledPreference() async {
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults,
            preferences: makePrefs(autoEnabled: false),
            currentVersion: SemanticVersion(string: "0.1.0")
        )
        await checker.checkNow()
        XCTAssertEqual(fetcher.callCount, 1)
    }
}
