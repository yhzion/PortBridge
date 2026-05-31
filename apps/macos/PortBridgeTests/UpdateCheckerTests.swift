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

    func test_checkNow_doubleDigitMinorIsNewer() async {
        // 0.10.0 > 0.9.0 — locks the core numeric comparison across the FFI boundary
        // (the lexicographic trap a naive string compare would fall into). Replaces
        // the macOS-side coverage removed with Swift's hand-rolled Comparable.
        let fetcher = MockReleaseFetcher(result: .success(release("v0.10.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.9.0")
        )
        await checker.checkNow()
        XCTAssertEqual(checker.phase, .available(release("v0.10.0")))
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

    // MARK: - Presenter behavior

    func test_autoCheck_presentsAvailableOnFirstDetection() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow()
        XCTAssertEqual(presenter.availableCalls.count, 1)
        XCTAssertEqual(presenter.availableCalls.first?.tagName, "v0.2.0")
    }

    func test_autoCheck_doesNotRepresentSameVersionOnSecondCheck() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow()
        await checker.checkNow()
        XCTAssertEqual(presenter.availableCalls.count, 1)
    }

    func test_autoCheck_representsWhenHigherVersionAppears() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow()
        fetcher.result = .success(release("v0.3.0"))
        await checker.checkNow()
        XCTAssertEqual(presenter.availableCalls.count, 2)
    }

    func test_manualCheck_presentsAvailableEveryTime() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow(manual: true)
        await checker.checkNow(manual: true)
        XCTAssertEqual(presenter.availableCalls.count, 2)
    }

    func test_manualCheck_presentsUpToDate_whenAlreadyLatest() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.2.0"),
            presenter: presenter
        )
        await checker.checkNow(manual: true)
        XCTAssertEqual(presenter.upToDateCalls, ["0.2.0"])
        XCTAssertTrue(presenter.availableCalls.isEmpty)
        XCTAssertTrue(presenter.failedCalls.isEmpty)
    }

    func test_autoCheck_doesNotPresentOnUpToDate() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.2.0"),
            presenter: presenter
        )
        await checker.checkNow()
        XCTAssertTrue(presenter.upToDateCalls.isEmpty)
    }

    func test_manualCheck_presentsFailed_onNetworkError() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(
            result: .failure(UpdateCheckError.network(URLError(.notConnectedToInternet)))
        )
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow(manual: true)
        XCTAssertEqual(presenter.failedCalls.count, 1)
        XCTAssertTrue(
            presenter.failedCalls[0].contains("Network"),
            "Expected human-readable network reason, got: \(presenter.failedCalls[0])"
        )
    }

    func test_autoCheck_doesNotPresentOnFailed() async {
        let presenter = MockUpdatePresenter()
        let fetcher = MockReleaseFetcher(
            result: .failure(UpdateCheckError.httpStatus(500))
        )
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow()
        XCTAssertTrue(presenter.failedCalls.isEmpty)
    }

    func test_skipChoice_marksVersionSkipped() async {
        let presenter = MockUpdatePresenter()
        presenter.availableResponses = [.skip]
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow(manual: true)
        XCTAssertEqual(checker.skippedVersion, SemanticVersion(string: "0.2.0"))
        if case .upToDate = checker.phase { } else {
            XCTFail("Expected .upToDate after Skip, got \(checker.phase)")
        }
    }

    func test_remindLaterChoice_leavesAvailable() async {
        let presenter = MockUpdatePresenter()
        presenter.availableResponses = [.remindLater]
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            presenter: presenter
        )
        await checker.checkNow(manual: true)
        XCTAssertNil(checker.skippedVersion)
        XCTAssertEqual(checker.phase, .available(release("v0.2.0")))
    }
}
