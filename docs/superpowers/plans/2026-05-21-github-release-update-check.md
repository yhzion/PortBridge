# GitHub Release Update Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect new PortBridge releases on GitHub and surface them to the user via menu bar icon badge, menu items, and a one-time system notification banner.

**Architecture:** A separate `@Observable UpdateChecker` (MainActor) coordinates state and persistence; a `ReleaseFetcher` protocol abstracts HTTP for testability (mirrors `MockTunnelManager`/`MockCommandRunner` patterns); a `UpdateNotifier` wraps `UNUserNotificationCenter`. `MenuBarController` reads from `viewModel.updates.availableUpdate` and renders a CALayer badge on the status item button (template image preserved). CI injects the git tag into `MARKETING_VERSION` at build time.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Observation framework, XCTest with mock-injection pattern, GitHub Actions (`xcodebuild`), `UserNotifications`, `URLSession`.

**Spec reference:** `docs/superpowers/specs/2026-05-21-github-release-update-check-design.md`

---

## Setup Notes (read once before starting)

- **All new Swift files MUST be added to the PortBridge target** (test files to PortBridgeTests target). In Xcode: drag the file into the project navigator → check the appropriate target membership in the right inspector. Failing to do this causes `Cannot find 'X' in scope` build errors.
- **Test runner**: per project memory (`xcodebuild-test-launch-issue.md`), CLI `xcodebuild test` fails with LaunchServices issues. Run tests via Xcode GUI (⌘U). Each task's "verify" step assumes this.
- **Branch**: work in this worktree (`worktree-update-check-design-spec`). Each task gets its own commit.
- **Build target**: macOS, deployment target matches existing project.

---

## Task 1: SemanticVersion (value type + tests)

**Files:**
- Create: `PortBridge/Updates/SemanticVersion.swift`
- Create: `PortBridgeTests/SemanticVersionTests.swift`

- [ ] **Step 1: Create the new folder** `PortBridge/Updates/` in Finder or Xcode.

- [ ] **Step 2: Write the failing test file** `PortBridgeTests/SemanticVersionTests.swift`

```swift
import XCTest
@testable import PortBridge

final class SemanticVersionTests: XCTestCase {
    func test_parsesWithVPrefix() {
        XCTAssertEqual(SemanticVersion(string: "v0.2.0"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    func test_parsesWithoutVPrefix() {
        XCTAssertEqual(SemanticVersion(string: "0.2.0"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    func test_twoComponent_defaultsPatchToZero() {
        XCTAssertEqual(SemanticVersion(string: "0.2"),
                       SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    func test_rejectsPreRelease() {
        XCTAssertNil(SemanticVersion(string: "v1.0.0-beta.1"))
        XCTAssertNil(SemanticVersion(string: "1.0.0-rc.2"))
    }

    func test_rejectsGarbage() {
        XCTAssertNil(SemanticVersion(string: "abc"))
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertNil(SemanticVersion(string: "1"))
        XCTAssertNil(SemanticVersion(string: "1.2.3.4"))
    }

    func test_comparison_basic() {
        XCTAssertTrue(SemanticVersion(string: "0.2.0")! > SemanticVersion(string: "0.1.9")!)
    }

    func test_comparison_avoidsLexicographicTrap() {
        XCTAssertTrue(SemanticVersion(string: "0.10.0")! > SemanticVersion(string: "0.9.0")!)
    }

    func test_comparison_majorDominates() {
        XCTAssertTrue(SemanticVersion(string: "1.0.0")! > SemanticVersion(string: "0.99.99")!)
    }

    func test_string_roundtrip() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.string, "1.2.3")
    }
}
```

- [ ] **Step 3: Add the test file to the PortBridgeTests target** in Xcode.

- [ ] **Step 4: Build → confirm failure** (`Cannot find 'SemanticVersion'`).

- [ ] **Step 5: Implement** `PortBridge/Updates/SemanticVersion.swift`

```swift
import Foundation

struct SemanticVersion: Comparable, Sendable, Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(string: String) {
        var s = string
        if s.hasPrefix("v") { s.removeFirst() }
        let allowed: Set<Character> = Set("0123456789.")
        guard !s.isEmpty, s.allSatisfy({ allowed.contains($0) }) else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        let patch: Int
        if parts.count == 3 {
            guard let p = Int(parts[2]) else { return nil }
            patch = p
        } else {
            patch = 0
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    var string: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
```

- [ ] **Step 6: Add file to PortBridge target** in Xcode.

- [ ] **Step 7: Run tests (⌘U) — confirm all SemanticVersionTests pass.**

- [ ] **Step 8: Commit**

```bash
git add PortBridge/Updates/SemanticVersion.swift PortBridgeTests/SemanticVersionTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add SemanticVersion value type"
```

---

## Task 2: ReleaseInfo + JSON fixture + decoding tests

**Files:**
- Create: `PortBridge/Updates/ReleaseInfo.swift`
- Create: `PortBridgeTests/Fixtures/github-release-latest.json`
- Create: `PortBridgeTests/ReleaseInfoDecodingTests.swift`

- [ ] **Step 1: Create the fixture** `PortBridgeTests/Fixtures/github-release-latest.json`

```json
{
  "url": "https://api.github.com/repos/yhzion/PortBridge/releases/235829",
  "html_url": "https://github.com/yhzion/PortBridge/releases/tag/v0.2.0",
  "tag_name": "v0.2.0",
  "name": "v0.2.0",
  "draft": false,
  "prerelease": false,
  "created_at": "2026-05-21T10:00:00Z",
  "published_at": "2026-05-21T10:47:15Z",
  "body": "## Changes\n- Update check feature added"
}
```

- [ ] **Step 2: Add fixture to PortBridgeTests target as Resource** (Build Phases → Copy Bundle Resources). This should mirror existing fixtures in `PortBridgeTests/Fixtures/`.

- [ ] **Step 3: Write the failing test** `PortBridgeTests/ReleaseInfoDecodingTests.swift`

```swift
import XCTest
@testable import PortBridge

final class ReleaseInfoDecodingTests: XCTestCase {
    func test_decodesGitHubFixture() throws {
        let url = Bundle(for: type(of: self))
            .url(forResource: "github-release-latest", withExtension: "json")
        XCTAssertNotNil(url, "Fixture not bundled — check Copy Bundle Resources")

        let data = try Data(contentsOf: url!)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let info = try decoder.decode(ReleaseInfo.self, from: data)
        XCTAssertEqual(info.tagName, "v0.2.0")
        XCTAssertEqual(info.htmlURL.absoluteString,
                       "https://github.com/yhzion/PortBridge/releases/tag/v0.2.0")
        XCTAssertEqual(info.name, "v0.2.0")
        XCTAssertNotNil(info.publishedAt)
        XCTAssertEqual(info.version, SemanticVersion(major: 0, minor: 2, patch: 0))
    }
}
```

- [ ] **Step 4: Build → confirm failure** (`Cannot find 'ReleaseInfo'`).

- [ ] **Step 5: Implement** `PortBridge/Updates/ReleaseInfo.swift`

```swift
import Foundation

struct ReleaseInfo: Sendable, Decodable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?

    var version: SemanticVersion? { SemanticVersion(string: tagName) }
}
```

- [ ] **Step 6: Add file to PortBridge target.**

- [ ] **Step 7: Run tests (⌘U) — confirm ReleaseInfoDecodingTests passes.**

- [ ] **Step 8: Commit**

```bash
git add PortBridge/Updates/ReleaseInfo.swift PortBridgeTests/Fixtures/github-release-latest.json PortBridgeTests/ReleaseInfoDecodingTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add ReleaseInfo + decoding test"
```

---

## Task 3: ReleaseFetcher protocol + GitHub implementation

**Files:**
- Create: `PortBridge/Updates/ReleaseFetcher.swift`

(No unit test for the HTTP impl — URLSession mocking is heavy and low value here. The Mock will be added in Task 6.)

- [ ] **Step 1: Implement** `PortBridge/Updates/ReleaseFetcher.swift`

```swift
import Foundation

enum UpdateCheckError: Error, Equatable {
    case network(URLError)
    case httpStatus(Int)
    case decoding(String)
    case invalidResponse
}

protocol ReleaseFetcher: Sendable {
    func fetchLatest() async throws -> ReleaseInfo
}

struct GitHubReleaseFetcher: ReleaseFetcher {
    let owner: String
    let repo: String
    let session: URLSession
    let currentAppVersion: String

    init(owner: String,
         repo: String,
         currentAppVersion: String,
         session: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.currentAppVersion = currentAppVersion
        self.session = session
    }

    func fetchLatest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PortBridge/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw UpdateCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ReleaseInfo.self, from: data)
        } catch {
            throw UpdateCheckError.decoding(String(describing: error))
        }
    }
}
```

- [ ] **Step 2: Add file to PortBridge target.**

- [ ] **Step 3: Build — confirm no errors.**

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Updates/ReleaseFetcher.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add ReleaseFetcher protocol + GitHub impl"
```

---

## Task 4: Bundle.currentVersion extension

**Files:**
- Create: `PortBridge/Updates/BundleVersion.swift`

(No unit test — trivial wrapper around `CFBundleShortVersionString`. Behavior is verified end-to-end in Task 7's smoke test.)

- [ ] **Step 1: Implement** `PortBridge/Updates/BundleVersion.swift`

```swift
import Foundation

extension Bundle {
    /// Reads `CFBundleShortVersionString` and parses it as SemanticVersion.
    /// Returns nil if the key is missing or the value is not a valid SemVer triple.
    var currentVersion: SemanticVersion? {
        guard let s = infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return SemanticVersion(string: s)
    }
}
```

- [ ] **Step 2: Add file to PortBridge target.**

- [ ] **Step 3: Build — confirm no errors.**

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Updates/BundleVersion.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add Bundle.currentVersion convenience"
```

---

## Task 5: AppPreferences — add automaticUpdateCheckEnabled

**Files:**
- Modify: `PortBridge/Storage/AppPreferences.swift`
- Modify: `PortBridgeTests/AppPreferencesTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `PortBridgeTests/AppPreferencesTests.swift` (inside the class, before the closing brace):

```swift
    func test_automaticUpdateCheckEnabled_defaultsToTrue() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertTrue(prefs.automaticUpdateCheckEnabled)
    }

    func test_automaticUpdateCheckEnabled_persists() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        prefs.automaticUpdateCheckEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "PortBridge.AutomaticUpdateCheckEnabled"))

        let prefs2 = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertFalse(prefs2.automaticUpdateCheckEnabled)
    }
```

- [ ] **Step 2: Build → confirm failure** (no `automaticUpdateCheckEnabled` property).

- [ ] **Step 3: Modify** `PortBridge/Storage/AppPreferences.swift` — add the property and key.

After the `launchAtLoginKey` line, add:

```swift
    private let automaticUpdateCheckEnabledKey = "PortBridge.AutomaticUpdateCheckEnabled"
```

After the `launchAtLogin` property block (around line 39), add:

```swift
    var automaticUpdateCheckEnabled: Bool {
        didSet {
            guard !suppressApply, automaticUpdateCheckEnabled != oldValue else { return }
            defaults.set(automaticUpdateCheckEnabled, forKey: automaticUpdateCheckEnabledKey)
        }
    }
```

In the `init(...)`, after the `defaults.set(systemEnabled, forKey: launchAtLoginKey)` line (around line 59), add:

```swift
        if defaults.object(forKey: automaticUpdateCheckEnabledKey) == nil {
            self.automaticUpdateCheckEnabled = true
        } else {
            self.automaticUpdateCheckEnabled = defaults.bool(forKey: automaticUpdateCheckEnabledKey)
        }
```

- [ ] **Step 4: Build — confirm no errors. Run tests (⌘U) — confirm new tests pass and existing AppPreferencesTests still pass.**

- [ ] **Step 5: Commit**

```bash
git add PortBridge/Storage/AppPreferences.swift PortBridgeTests/AppPreferencesTests.swift
git commit -m "feat(prefs): add automaticUpdateCheckEnabled (default true)"
```

---

## Task 6: UpdateChecker core + MockReleaseFetcher + tests

**Files:**
- Create: `PortBridge/Updates/UpdateChecker.swift`
- Create: `PortBridgeTests/MockReleaseFetcher.swift`
- Create: `PortBridgeTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Create the mock** `PortBridgeTests/MockReleaseFetcher.swift`

```swift
import Foundation
@testable import PortBridge

final class MockReleaseFetcher: ReleaseFetcher, @unchecked Sendable {
    var result: Result<ReleaseInfo, Error>
    private(set) var callCount = 0

    init(result: Result<ReleaseInfo, Error>) {
        self.result = result
    }

    func fetchLatest() async throws -> ReleaseInfo {
        callCount += 1
        return try result.get()
    }
}
```

- [ ] **Step 2: Add mock to PortBridgeTests target.**

- [ ] **Step 3: Write the failing tests** `PortBridgeTests/UpdateCheckerTests.swift`

```swift
import XCTest
@testable import PortBridge

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
```

- [ ] **Step 4: Add test file to PortBridgeTests target.**

- [ ] **Step 5: Build → confirm failure** (no `UpdateChecker` type).

- [ ] **Step 6: Implement** `PortBridge/Updates/UpdateChecker.swift`

```swift
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
```

- [ ] **Step 7: Add file to PortBridge target.**

- [ ] **Step 8: Run tests (⌘U) — confirm all UpdateCheckerTests pass.**

- [ ] **Step 9: Commit**

```bash
git add PortBridge/Updates/UpdateChecker.swift PortBridgeTests/MockReleaseFetcher.swift PortBridgeTests/UpdateCheckerTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add UpdateChecker with skip + 24h debounce"
```

---

## Task 7: Wire UpdateChecker into AppViewModel and AppDelegate

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Modify: `PortBridge/PortBridgeApp.swift`

- [ ] **Step 1: Modify** `PortBridge/ViewModels/AppViewModel.swift`

After the `let preferences: AppPreferences` line (around line 27 post-swiftformat), add:

```swift
    let updates: UpdateChecker
```

In the `init(...)` signature (around lines 76-82 post-swiftformat), add an optional parameter:

```swift
    init(
        store: ServerStore? = nil,
        scanner: PortScanner? = nil,
        tunnels: TunnelManaging? = nil,
        favorites: FavoriteStore? = nil,
        preferences: AppPreferences? = nil,
        updates: UpdateChecker? = nil
    ) {
```

In the init body, after the `self.preferences = preferences ?? AppPreferences.production()` line, add:

```swift
        let resolvedPrefs = self.preferences
        self.updates = updates ?? UpdateChecker(
            fetcher: GitHubReleaseFetcher(
                owner: "yhzion",
                repo: "PortBridge",
                currentAppVersion: Bundle.main.currentVersion?.string ?? "0.0.0"
            ),
            defaults: .standard,
            preferences: resolvedPrefs,
            currentVersion: Bundle.main.currentVersion
        )
```

(The `resolvedPrefs` local is needed because `self.preferences` cannot be referenced before all stored properties are initialized in some configurations; using a local makes the order explicit.)

- [ ] **Step 2: Modify** `PortBridge/PortBridgeApp.swift` — in `applicationDidFinishLaunching` (around line 56), after the favorites task block, add:

```swift
        // Background update check on launch (no-op if disabled or recently checked).
        Task { @MainActor in
            await viewModel.updates.checkIfDue()
        }
```

- [ ] **Step 3: Build & run the app. Verify in Console.app or Xcode logs**: filter for `subsystem:PortBridge category:UpdateChecker`. On a fresh launch with internet, you should see no errors and the check should complete. (No UI changes yet — that's Task 8-10.)

- [ ] **Step 4: Run all existing tests (⌘U) — confirm AppViewModel-related tests still pass.**

- [ ] **Step 5: Commit**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridge/PortBridgeApp.swift
git commit -m "feat(updates): wire UpdateChecker into AppViewModel + launch hook"
```

---

## Task 8: MenuBarController — "Update available" menu section

**Files:**
- Modify: `PortBridge/MenuBarController.swift`

- [ ] **Step 1: Add new `@objc` action methods** at the bottom of the `MenuBarController` class (before the closing brace, near the other `@objc` methods around line 175+):

```swift
    @objc private func openReleasePage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func skipCurrentRelease() {
        viewModel.updates.skipCurrent()
    }
```

- [ ] **Step 2: Modify** `buildMenu()` — at the very top of the method, after `menu.autoenablesItems = false`, insert the update section:

```swift
        // Update available (only when a non-skipped newer release exists)
        if let release = viewModel.updates.availableUpdate {
            let tag = release.tagName
            let item = NSMenuItem(
                title: "Update available — \(tag)",
                action: #selector(openReleasePage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = release.htmlURL
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                 accessibilityDescription: nil)

            let submenu = NSMenu()
            let skip = NSMenuItem(title: "Skip This Version",
                                  action: #selector(skipCurrentRelease),
                                  keyEquivalent: "")
            skip.target = self
            submenu.addItem(skip)

            let notes = NSMenuItem(title: "Show Release Notes…",
                                   action: #selector(openReleasePage(_:)),
                                   keyEquivalent: "")
            notes.target = self
            notes.representedObject = release.htmlURL
            submenu.addItem(notes)

            item.submenu = submenu
            menu.addItem(item)
            menu.addItem(.separator())
        }
```

- [ ] **Step 3: Build & manual smoke test**:
  - In `AppViewModel.init`, temporarily set `currentVersion: SemanticVersion(string: "0.0.1")` so the GitHub `v0.1.0` (or whatever's latest) appears as new.
  - Build & run. Open the menu bar icon menu. Verify "Update available — v0.1.0" appears at the top with the down-arrow icon and the submenu has both items.
  - Click "Update available" → browser opens to the release page.
  - Reset the temporary version override before committing.

- [ ] **Step 4: Commit**

```bash
git add PortBridge/MenuBarController.swift
git commit -m "feat(menu): show 'Update available' item with Skip submenu"
```

---

## Task 9: MenuBarController — auto-check toggle + manual "Check Now"

**Files:**
- Modify: `PortBridge/MenuBarController.swift`

- [ ] **Step 1: Add `@objc` action methods** (same area as Task 8):

```swift
    @objc private func toggleAutomaticUpdateCheck() {
        viewModel.preferences.automaticUpdateCheckEnabled.toggle()
    }

    @objc private func checkForUpdatesNow() {
        Task { @MainActor in
            await viewModel.updates.checkNow()
        }
    }
```

- [ ] **Step 2: Modify** `buildMenu()` — find the section that adds `dockItem` (around the "Show in Dock" item). After `menu.addItem(dockItem)`, add:

```swift
        let autoCheckItem = NSMenuItem(
            title: "Check for Updates Automatically",
            action: #selector(toggleAutomaticUpdateCheck),
            keyEquivalent: ""
        )
        autoCheckItem.target = self
        autoCheckItem.state = viewModel.preferences.automaticUpdateCheckEnabled ? .on : .off
        menu.addItem(autoCheckItem)

        let checkNowItem: NSMenuItem
        if case .failed = viewModel.updates.phase {
            checkNowItem = NSMenuItem(
                title: "Check failed — try again",
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
        } else if case .checking = viewModel.updates.phase {
            checkNowItem = NSMenuItem(title: "Checking…",
                                      action: nil, keyEquivalent: "")
            checkNowItem.isEnabled = false
        } else {
            checkNowItem = NSMenuItem(
                title: "Check for Updates Now…",
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
        }
        checkNowItem.target = self
        menu.addItem(checkNowItem)
```

- [ ] **Step 3: Build & manual test**:
  - Open menu. Verify "Check for Updates Automatically ✓" appears.
  - Click it — checkmark should toggle off. Re-open menu to confirm state persisted.
  - Click "Check for Updates Now…". Watch console logs to see check fire. Re-open menu — should be "Check for Updates Now…" again (unless network fails).

- [ ] **Step 4: Commit**

```bash
git add PortBridge/MenuBarController.swift
git commit -m "feat(menu): add auto-check toggle and manual Check Now"
```

---

## Task 10: MenuBarController — CALayer badge on status item button

**Files:**
- Modify: `PortBridge/MenuBarController.swift`

- [ ] **Step 1: Add a stored property** at the top of the `MenuBarController` class (near `private var statusItem: NSStatusItem?`):

```swift
    private var badgeLayer: CALayer?
```

- [ ] **Step 2: Add the badge management methods** at the bottom of the class:

```swift
    private func updateBadge(visible: Bool) {
        guard let button = statusItem?.button else { return }
        if visible {
            if badgeLayer == nil {
                button.wantsLayer = true
                let layer = CALayer()
                layer.backgroundColor = NSColor.systemBlue.cgColor
                layer.cornerRadius = 2
                button.layer?.addSublayer(layer)
                badgeLayer = layer
            }
            layoutBadge()
        } else {
            badgeLayer?.removeFromSuperlayer()
            badgeLayer = nil
        }
    }

    private func layoutBadge() {
        guard let button = statusItem?.button, let layer = badgeLayer else { return }
        let size: CGFloat = 4
        let inset: CGFloat = 1
        let x = button.bounds.maxX - size - inset
        let y = button.bounds.maxY - size - inset
        layer.frame = CGRect(x: x, y: y, width: size, height: size)
    }
```

- [ ] **Step 3: Modify** `observeIconState()` — extend the tracked reads and the onChange action.

The current (post-swiftlint) shape already uses `[weak self]` in the `withObservationTracking` closure. Replace the entire `observeIconState()` method with:

```swift
    private func observeIconState() {
        withObservationTracking { [weak self] in
            _ = self?.viewModel.isAnyFavoriteActive
            _ = self?.viewModel.updates.availableUpdate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshIcon()
                self.updateBadge(visible: self.viewModel.updates.availableUpdate != nil)
                self.observeIconState()
            }
        }
    }
```

- [ ] **Step 4: Modify** `install()` — at the end of the method (after the existing `observeIconState()` call), add an initial badge render:

```swift
        updateBadge(visible: viewModel.updates.availableUpdate != nil)
```

- [ ] **Step 5: Manual test**:
  - Use the same `currentVersion: "0.0.1"` override from Task 8 so an update appears.
  - Build & run. The menu bar icon should show a small blue dot at the top-right.
  - Open menu, click "Skip This Version". The dot should disappear.
  - Reset the version override.

- [ ] **Step 6: Commit**

```bash
git add PortBridge/MenuBarController.swift
git commit -m "feat(menu): add blue dot badge on status item when update available"
```

---

## Task 11: UpdateNotifier (UNUserNotificationCenter wrapper)

**Files:**
- Create: `PortBridge/Updates/UpdateNotifier.swift`
- Create: `PortBridgeTests/MockUpdateNotifier.swift`

- [ ] **Step 1: Create the mock** `PortBridgeTests/MockUpdateNotifier.swift`

```swift
import Foundation
@testable import PortBridge

@MainActor
final class MockUpdateNotifier: UpdateNotifying {
    private(set) var notifyCalls: [ReleaseInfo] = []

    func notify(release: ReleaseInfo) async {
        notifyCalls.append(release)
    }
}
```

- [ ] **Step 2: Add mock to PortBridgeTests target.**

- [ ] **Step 3: Implement** `PortBridge/Updates/UpdateNotifier.swift`

```swift
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
```

- [ ] **Step 4: Add file to PortBridge target.**

- [ ] **Step 5: Build — confirm no errors.** (No unit test for the real impl — `UNUserNotificationCenter` requires entitlements and shows real dialogs.)

- [ ] **Step 6: Commit**

```bash
git add PortBridge/Updates/UpdateNotifier.swift PortBridgeTests/MockUpdateNotifier.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(updates): add UpdateNotifier (UNUserNotificationCenter wrapper)"
```

---

## Task 12: UpdateChecker integrates UpdateNotifier with first-detection logic

**Files:**
- Modify: `PortBridge/Updates/UpdateChecker.swift`
- Modify: `PortBridgeTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Add failing tests** — append to `UpdateCheckerTests`:

```swift
    func test_notifiesOnFirstDetection() async {
        let notifier = MockUpdateNotifier()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            notifier: notifier
        )
        await checker.checkNow()
        XCTAssertEqual(notifier.notifyCalls.count, 1)
        XCTAssertEqual(notifier.notifyCalls.first?.tagName, "v0.2.0")
        XCTAssertEqual(checker.lastNotifiedVersion, SemanticVersion(string: "0.2.0"))
    }

    func test_doesNotNotifyTwiceForSameVersion() async {
        let notifier = MockUpdateNotifier()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            notifier: notifier
        )
        await checker.checkNow()
        await checker.checkNow()
        XCTAssertEqual(notifier.notifyCalls.count, 1)
    }

    func test_notifiesAgainForHigherVersion() async {
        let notifier = MockUpdateNotifier()
        let fetcher = MockReleaseFetcher(result: .success(release("v0.2.0")))
        let checker = UpdateChecker(
            fetcher: fetcher, defaults: defaults, preferences: makePrefs(),
            currentVersion: SemanticVersion(string: "0.1.0"),
            notifier: notifier
        )
        await checker.checkNow()

        fetcher.result = .success(release("v0.3.0"))
        await checker.checkNow()
        XCTAssertEqual(notifier.notifyCalls.count, 2)
    }
```

- [ ] **Step 2: Modify** `UpdateChecker.swift` — add the notifier dependency.

After the `now` property declaration, add:

```swift
    @ObservationIgnored private let notifier: UpdateNotifying?
```

Change the initializer signature (add `notifier: UpdateNotifying? = nil`):

```swift
    init(fetcher: ReleaseFetcher,
         defaults: UserDefaults,
         preferences: AppPreferences,
         currentVersion: SemanticVersion?,
         notifier: UpdateNotifying? = nil,
         now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.notifier = notifier
        self.now = now
        // … existing defaults loads unchanged
        self.lastCheckedAt = defaults.object(forKey: Keys.lastCheckedAt) as? Date
        self.skippedVersion = defaults.string(forKey: Keys.skippedVersion)
            .flatMap(SemanticVersion.init(string:))
        self.lastNotifiedVersion = defaults.string(forKey: Keys.lastNotifiedVersion)
            .flatMap(SemanticVersion.init(string:))
    }
```

In `checkNow()`, inside the `if isNewer && !isSkipped` branch, before setting `phase`, add the notification trigger:

```swift
            if isNewer && !isSkipped {
                if lastNotifiedVersion != remote {
                    lastNotifiedVersion = remote
                    defaults.set(remote.string, forKey: Keys.lastNotifiedVersion)
                    if let notifier {
                        await notifier.notify(release: info)
                    }
                }
                phase = .available(info)
            } else {
                phase = .upToDate(checkedAt: timestamp)
            }
```

- [ ] **Step 3: Run tests (⌘U) — confirm new notification tests pass and all prior UpdateCheckerTests still pass.**

- [ ] **Step 4: Wire the notifier into the real app** — modify `AppViewModel.init` from Task 7. Change the `UpdateChecker(...)` construction to pass the notifier:

```swift
        self.updates = updates ?? UpdateChecker(
            fetcher: GitHubReleaseFetcher(
                owner: "yhzion",
                repo: "PortBridge",
                currentAppVersion: Bundle.main.currentVersion?.string ?? "0.0.0"
            ),
            defaults: .standard,
            preferences: resolvedPrefs,
            currentVersion: Bundle.main.currentVersion,
            notifier: UpdateNotifier()
        )
```

- [ ] **Step 5: Manual smoke test**:
  - Apply the `currentVersion: "0.0.1"` override from Task 8.
  - First launch after override: macOS asks for notification permission → grant → banner appears for "PortBridge update available v0.1.0".
  - Quit and relaunch. No second banner (dot/menu still show).
  - Reset the version override.

- [ ] **Step 6: Commit**

```bash
git add PortBridge/Updates/UpdateChecker.swift PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/UpdateCheckerTests.swift
git commit -m "feat(updates): notify via system banner on first detection only"
```

---

## Task 13: PRIVACY.md

**Files:**
- Create: `docs/PRIVACY.md`

- [ ] **Step 1: Create** `docs/PRIVACY.md`

```markdown
# PortBridge Privacy

PortBridge does not collect, transmit, or store any personal data.

## Update checks

To detect new releases, PortBridge sends anonymous HTTPS `GET` requests to
`https://api.github.com/repos/yhzion/PortBridge/releases/latest`. These requests
include only a generic `User-Agent` header (`PortBridge/<version>`) as required
by the GitHub API. No user data, identifiers beyond your IP address (visible to
GitHub by virtue of the connection), or usage statistics are sent.

Update checks fire:

- Once when the app launches (subject to a 24-hour debounce)
- When you select "Check for Updates Now…" from the menu bar

You can disable automatic checks in the menu bar by unticking
"Check for Updates Automatically". Manual checks remain available.

## SSH and forwarding

PortBridge spawns local `ssh` processes to establish port forwards to the
servers you configure. Connection data (server addresses, credentials handled
by SSH) never leaves your machine via PortBridge itself.

## No telemetry

PortBridge has no analytics, crash reporting, or telemetry of any kind.
```

- [ ] **Step 2: Commit**

```bash
git add docs/PRIVACY.md
git commit -m "docs: add PRIVACY.md covering update checks and SSH"
```

---

## Wrap-up

After Task 13:

- [ ] **Final verification — run the full test suite (⌘U)**. All tests should pass.
- [ ] **Build & launch the app locally**. The Run Script (`Scripts/inject-version.sh`, already on main) writes `CFBundleShortVersionString = "0.0.0"` and `CFBundleVersion = "dev-<sha>"` into the built `Info.plist` for untagged builds. `0.0.0 < 0.1.0` (current live release) → badge + menu item + banner all appear. This is the expected dev-build behavior (spec § 5).
- [ ] **Verify "Skip This Version" hides the dot/item**, and that disabling "Check for Updates Automatically" stops launch-time checks but leaves "Check Now" functional.
- [ ] **Push branch and open PR** (or sequence of PRs aligned to the 4 spec phases — see spec § 10).

The next tagged release (`v0.2.0`) will validate the end-to-end flow: `inject-version.sh` writes `0.2.0`, the GitHub Release workflow uploads it, and users still on `v0.1.0` see the badge/menu/banner on their next launch. **No CI workflow changes are needed** — version injection is already handled by the build phase.
