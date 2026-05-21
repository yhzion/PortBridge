# Menu Bar Extras Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PortBridge에 메뉴바 드롭다운 UI, 즐겨찾기(★) 자동 시작, Dock 표시 토글, 로그인 시 자동 시작을 추가한다.

**Architecture:** 새 `FavoriteStore`와 `AppPreferences`를 `AppViewModel`이 보유 — 메인 창과 신규 `MenuBarExtra` Scene이 동일 `@Observable` ViewModel을 환경에서 구독한다. Dock 토글은 `NSApp.setActivationPolicy` 런타임 호출, 로그인 시 시작은 `SMAppService.mainApp`로 시스템 등록.

**Tech Stack:** Swift 5.10, SwiftUI (macOS 14+), Observation, ServiceManagement (SMAppService), AppKit (NSApp activation policy), XCTest, UserDefaults JSON persistence.

**참고 spec:** [docs/superpowers/specs/2026-05-21-menubar-extras-design.md](../specs/2026-05-21-menubar-extras-design.md)

**테스트 실행:** `xcodebuild test`는 LaunchServices 환경 이슈로 CLI 실패 — **모든 단위 테스트는 Xcode GUI에서 ⌘U로 실행**한다 ([memory:xcodebuild-test-launch-issue](../../../.claude/projects/-Users-youngho-jeon-datamaker-PortBridge/memory/xcodebuild-test-launch-issue.md)). `xcodebuild build`는 사용 가능.

**Xcode 프로젝트 등록:** 모든 신규 `.swift` 파일은 Xcode UI에서 우클릭 → "Add Files to PortBridge…" 또는 파일 인스펙터에서 Target Membership 체크로 PortBridge / PortBridgeTests 타겟에 등록해야 컴파일된다. 각 신규 파일 Create 단계에서 명시한다.

---

## 파일 구조 (선결)

신규 파일:
- `PortBridge/Models/FavoriteKey.swift` — 즐겨찾기 키 (serverId + remotePort)
- `PortBridge/Storage/FavoriteStore.swift` — Set<FavoriteKey> 영속화 (ServerStore 패턴)
- `PortBridge/Storage/AppPreferences.swift` — launchAtLogin / showInDock 영속화 + side effect
- `PortBridge/Views/MenuBarContent.swift` — 메뉴바 드롭다운 SwiftUI
- `PortBridgeTests/FavoriteStoreTests.swift`
- `PortBridgeTests/AppPreferencesTests.swift`
- `PortBridgeTests/AppViewModelFavoritesTests.swift`

수정 파일:
- `PortBridge/ViewModels/AppViewModel.swift` — favorites/preferences/FavoriteRow/startFavoritesIfEnabled 추가
- `PortBridge/Views/ForwardingRowView.swift` — leading 별 버튼 + isFavorite/onFavoriteToggle 추가
- `PortBridge/Views/ServerSectionView.swift` — ForwardingRowView 호출 인자 추가 (isFavorite/onFavoriteToggle 전달)
- `PortBridge/PortBridgeApp.swift` — MenuBarExtra Scene 추가, activation policy 초기화, 즐겨찾기 자동 시작 wiring

---

## Task 1: `FavoriteKey` 모델

**Files:**
- Create: `PortBridge/Models/FavoriteKey.swift`
- (테스트는 Task 2 `FavoriteStoreTests`에서 함께 검증)

- [ ] **Step 1: 파일 생성**

`PortBridge/Models/FavoriteKey.swift`:

```swift
import Foundation

nonisolated struct FavoriteKey: Hashable, Codable {
    let serverId: UUID
    let remotePort: Int
}
```

- [ ] **Step 2: Xcode 프로젝트에 등록**

Xcode 열기 → Project Navigator → `PortBridge/Models` 그룹에 파일 추가. Target Membership에서 **PortBridge** 체크, **PortBridgeTests**도 체크 (테스트에서 사용).

- [ ] **Step 3: 빌드 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build -quiet 2>&1 | tail -5
```

기대: `BUILD SUCCEEDED`.

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Models/FavoriteKey.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(model): add FavoriteKey (serverId, remotePort)"
```

---

## Task 2: `FavoriteStore` + 테스트

**Files:**
- Create: `PortBridge/Storage/FavoriteStore.swift`
- Create: `PortBridgeTests/FavoriteStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`PortBridgeTests/FavoriteStoreTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class FavoriteStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.FavoriteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_add_insertsFavorite() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        XCTAssertTrue(store.contains(key))
        XCTAssertEqual(store.favorites.count, 1)
    }

    func test_add_isIdempotent() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        store.add(key)
        XCTAssertEqual(store.favorites.count, 1)
    }

    func test_remove_deletesFavorite() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.add(key)
        store.remove(key)
        XCTAssertFalse(store.contains(key))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func test_toggle_addsThenRemoves() {
        let store = FavoriteStore(defaults: defaults)
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        store.toggle(key)
        XCTAssertTrue(store.contains(key))
        store.toggle(key)
        XCTAssertFalse(store.contains(key))
    }

    func test_persistence_survivesNewInstance() {
        let key = FavoriteKey(serverId: UUID(), remotePort: 5432)
        let store1 = FavoriteStore(defaults: defaults)
        store1.add(key)

        let store2 = FavoriteStore(defaults: defaults)
        XCTAssertTrue(store2.contains(key))
    }

    func test_multipleKeys_storedIndependently() {
        let store = FavoriteStore(defaults: defaults)
        let serverA = UUID()
        let serverB = UUID()
        store.add(FavoriteKey(serverId: serverA, remotePort: 5432))
        store.add(FavoriteKey(serverId: serverB, remotePort: 5432))
        store.add(FavoriteKey(serverId: serverA, remotePort: 8080))
        XCTAssertEqual(store.favorites.count, 3)
    }
}
```

- [ ] **Step 2: 테스트 파일 Xcode 등록**

Xcode → PortBridgeTests 그룹에 추가. Target Membership = **PortBridgeTests**만.

- [ ] **Step 3: 테스트 빌드 실패 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build-for-testing -quiet 2>&1 | tail -10
```

기대: `Cannot find 'FavoriteStore' in scope` 같은 컴파일 에러.

- [ ] **Step 4: 최소 구현**

`PortBridge/Storage/FavoriteStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class FavoriteStore {
    private(set) var favorites: Set<FavoriteKey> = []
    private let defaultsKey = "PortBridge.Favorites.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ key: FavoriteKey) {
        guard !favorites.contains(key) else { return }
        favorites.insert(key)
        save()
    }

    func remove(_ key: FavoriteKey) {
        guard favorites.contains(key) else { return }
        favorites.remove(key)
        save()
    }

    func toggle(_ key: FavoriteKey) {
        if favorites.contains(key) {
            remove(key)
        } else {
            add(key)
        }
    }

    func contains(_ key: FavoriteKey) -> Bool {
        favorites.contains(key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(favorites)) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteKey].self, from: data) else { return }
        favorites = Set(decoded)
    }
}
```

- [ ] **Step 5: Xcode 등록**

`PortBridge/Storage` 그룹에 추가. Target Membership = **PortBridge** + **PortBridgeTests**.

- [ ] **Step 6: 테스트 실행 — Xcode GUI**

Xcode에서 ⌘U → Test Navigator에서 `FavoriteStoreTests` 6개 모두 ✓ 확인.

- [ ] **Step 7: 커밋**

```bash
git add PortBridge/Storage/FavoriteStore.swift PortBridgeTests/FavoriteStoreTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(storage): add FavoriteStore with UserDefaults JSON persistence"
```

---

## Task 3: `AppPreferences` + 테스트

**Files:**
- Create: `PortBridge/Storage/AppPreferences.swift`
- Create: `PortBridgeTests/AppPreferencesTests.swift`

`AppPreferences`는 두 가지 책임을 가진다:
1. UserDefaults 영속화 (`showInDock`, `launchAtLogin` 사용자 의도)
2. **Side effect**: `showInDock` setter → `NSApp.setActivationPolicy`, `launchAtLogin` setter → `SMAppService.mainApp.register/unregister`

테스트 가능성을 위해 side effect를 의존 주입 가능한 클로저로 추출한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PortBridgeTests/AppPreferencesTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_defaultValues_showInDockTrue_launchAtLoginFalse() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertTrue(prefs.showInDock)
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func test_showInDock_set_callsApplyAndPersists() {
        var captured: [Bool] = []
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { captured.append($0) },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        prefs.showInDock = false
        XCTAssertEqual(captured, [false])
        XCTAssertFalse(defaults.bool(forKey: "PortBridge.ShowInDock"))

        let prefs2 = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        XCTAssertFalse(prefs2.showInDock)
    }

    func test_launchAtLogin_set_true_callsRegisterAndPersists() {
        var capturedDesired: [Bool] = []
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { desired in
                capturedDesired.append(desired)
                return true
            },
            readLaunchAtLogin: { false }
        )
        prefs.launchAtLogin = true
        XCTAssertEqual(capturedDesired, [true])
        XCTAssertTrue(prefs.launchAtLogin)
    }

    func test_launchAtLogin_set_applyFails_keepsPreviousState() {
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in false },
            readLaunchAtLogin: { false }
        )
        prefs.launchAtLogin = true
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func test_launchAtLogin_initialState_syncsWithSystem() {
        defaults.set(true, forKey: "PortBridge.LaunchAtLogin")
        let prefs = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        // 시스템이 false라고 보고하면 사용자 영속값보다 우선
        XCTAssertFalse(prefs.launchAtLogin)
    }
}
```

- [ ] **Step 2: 테스트 파일 Xcode 등록**

PortBridgeTests 타겟에 추가.

- [ ] **Step 3: 테스트 빌드 실패 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build-for-testing -quiet 2>&1 | tail -10
```

기대: `Cannot find 'AppPreferences' in scope` 컴파일 에러.

- [ ] **Step 4: 최소 구현**

`PortBridge/Storage/AppPreferences.swift`:

```swift
import Foundation
import Observation
import AppKit
import ServiceManagement

@MainActor
@Observable
final class AppPreferences {
    private let defaults: UserDefaults
    private let applyShowInDock: (Bool) -> Void
    private let applyLaunchAtLogin: (Bool) -> Bool

    private let showInDockKey = "PortBridge.ShowInDock"
    private let launchAtLoginKey = "PortBridge.LaunchAtLogin"

    @ObservationIgnored
    private var suppressApply = false

    var showInDock: Bool {
        didSet {
            guard !suppressApply, showInDock != oldValue else { return }
            defaults.set(showInDock, forKey: showInDockKey)
            applyShowInDock(showInDock)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !suppressApply, launchAtLogin != oldValue else { return }
            let succeeded = applyLaunchAtLogin(launchAtLogin)
            if !succeeded {
                suppressApply = true
                launchAtLogin = oldValue
                suppressApply = false
                return
            }
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        applyShowInDock: @escaping (Bool) -> Void,
        applyLaunchAtLogin: @escaping (Bool) -> Bool,
        readLaunchAtLogin: () -> Bool
    ) {
        self.defaults = defaults
        self.applyShowInDock = applyShowInDock
        self.applyLaunchAtLogin = applyLaunchAtLogin

        if defaults.object(forKey: showInDockKey) == nil {
            self.showInDock = true
        } else {
            self.showInDock = defaults.bool(forKey: showInDockKey)
        }

        // 시스템 상태가 진실의 원천
        let systemEnabled = readLaunchAtLogin()
        self.launchAtLogin = systemEnabled
        defaults.set(systemEnabled, forKey: launchAtLoginKey)
    }
}

extension AppPreferences {
    /// 실제 macOS API에 연결된 프로덕션 인스턴스 팩토리.
    static func production(defaults: UserDefaults = .standard) -> AppPreferences {
        AppPreferences(
            defaults: defaults,
            applyShowInDock: { show in
                NSApp.setActivationPolicy(show ? .regular : .accessory)
            },
            applyLaunchAtLogin: { desired in
                do {
                    if desired {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    return true
                } catch {
                    return false
                }
            },
            readLaunchAtLogin: {
                SMAppService.mainApp.status == .enabled
            }
        )
    }
}
```

- [ ] **Step 5: Xcode 등록**

`PortBridge/Storage` 그룹에 추가. Target Membership = **PortBridge** + **PortBridgeTests**.

`PortBridge` 타겟의 Frameworks 설정에 `ServiceManagement.framework` 추가:
Project → PortBridge Target → General → "Frameworks, Libraries, and Embedded Content" → "+" → ServiceManagement.framework → Embed = "Do Not Embed".

- [ ] **Step 6: 테스트 실행 — Xcode GUI**

⌘U → `AppPreferencesTests` 5개 모두 ✓.

- [ ] **Step 7: 커밋**

```bash
git add PortBridge/Storage/AppPreferences.swift PortBridgeTests/AppPreferencesTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(storage): add AppPreferences with showInDock/launchAtLogin + side effects"
```

---

## Task 4: `AppViewModel` — favorites 통합 + isFavorite/toggleFavorite

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Create: `PortBridgeTests/AppViewModelFavoritesTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`PortBridgeTests/AppViewModelFavoritesTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelFavoritesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AVMFavorites.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeViewModel() -> AppViewModel {
        let serverStore = ServerStore(defaults: defaults)
        let favoriteStore = FavoriteStore(defaults: defaults)
        let preferences = AppPreferences(
            defaults: defaults,
            applyShowInDock: { _ in },
            applyLaunchAtLogin: { _ in true },
            readLaunchAtLogin: { false }
        )
        return AppViewModel(
            store: serverStore,
            scanner: PortScanner(runner: MockCommandRunner()),
            tunnels: MockTunnelManager(),
            favorites: favoriteStore,
            preferences: preferences
        )
    }

    func test_isFavorite_falseInitially() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isFavorite(serverId: UUID(), port: 5432))
    }

    func test_toggleFavorite_addsThenRemoves() {
        let vm = makeViewModel()
        let serverId = UUID()
        vm.toggleFavorite(serverId: serverId, port: 5432)
        XCTAssertTrue(vm.isFavorite(serverId: serverId, port: 5432))
        vm.toggleFavorite(serverId: serverId, port: 5432)
        XCTAssertFalse(vm.isFavorite(serverId: serverId, port: 5432))
    }

    func test_toggleFavorite_independentPerServerAndPort() {
        let vm = makeViewModel()
        let serverA = UUID()
        let serverB = UUID()
        vm.toggleFavorite(serverId: serverA, port: 5432)
        XCTAssertTrue(vm.isFavorite(serverId: serverA, port: 5432))
        XCTAssertFalse(vm.isFavorite(serverId: serverB, port: 5432))
        XCTAssertFalse(vm.isFavorite(serverId: serverA, port: 5433))
    }
}
```

- [ ] **Step 2: 테스트 파일 Xcode 등록**

PortBridgeTests 타겟에 추가.

- [ ] **Step 3: 테스트 빌드 실패 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build-for-testing -quiet 2>&1 | tail -10
```

기대: `Extra argument 'favorites' in call`, `Cannot find 'isFavorite'` 등 컴파일 에러.

- [ ] **Step 4: `AppViewModel.swift` 수정**

`PortBridge/ViewModels/AppViewModel.swift`의 init 시그니처와 stored property 추가:

Stored property 섹션 (기존 `private(set) var errors` 뒤):

```swift
    let favorites: FavoriteStore
    let preferences: AppPreferences
```

init 시그니처를 다음으로 교체:

```swift
    init(
        store: ServerStore = ServerStore(),
        scanner: PortScanner = PortScanner(runner: ProcessCommandRunner()),
        tunnels: TunnelManager? = nil,
        favorites: FavoriteStore = FavoriteStore(),
        preferences: AppPreferences? = nil
    ) {
        self.store = store
        self.scanner = scanner
        let t = tunnels ?? TunnelManager()
        self.tunnels = t
        self.favorites = favorites
        self.preferences = preferences ?? AppPreferences.production()
        t.delegate = self
        rebuildSections()
    }
```

`// MARK: - Server CRUD` 직전에 새 MARK 섹션 추가:

```swift
    // MARK: - Favorites

    func isFavorite(serverId: UUID, port: Int) -> Bool {
        favorites.contains(FavoriteKey(serverId: serverId, remotePort: port))
    }

    func toggleFavorite(serverId: UUID, port: Int) {
        favorites.toggle(FavoriteKey(serverId: serverId, remotePort: port))
    }
```

- [ ] **Step 5: 테스트 실행 — Xcode GUI**

⌘U → `AppViewModelFavoritesTests` 3개 모두 ✓. **기존 AppViewModel* 테스트도 모두 ✓ 유지** 확인.

- [ ] **Step 6: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelFavoritesTests.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(viewmodel): wire FavoriteStore + AppPreferences, add isFavorite/toggleFavorite"
```

---

## Task 5: `AppViewModel` — `favoriteRows` / `nonFavoriteActive`

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Modify: `PortBridgeTests/AppViewModelFavoritesTests.swift` (추가 테스트)

- [ ] **Step 1: 실패하는 테스트 추가**

`PortBridgeTests/AppViewModelFavoritesTests.swift` 끝에 추가:

```swift
    func test_favoriteRows_emptyWhenNoFavorites() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.favoriteRows.isEmpty)
    }

    func test_favoriteRows_includesIdleFavorite_serverNameAndPortOnly() {
        let vm = makeViewModel()
        let server = Server(name: "db-prod", user: "ubuntu", host: "10.0.0.1")
        vm.addServer(server)
        vm.toggleFavorite(serverId: server.id, port: 5432)

        let rows = vm.favoriteRows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.serverDisplayName, "db-prod (10.0.0.1)")
        XCTAssertEqual(rows.first?.remotePort, 5432)
        XCTAssertNil(rows.first?.localPort)
        XCTAssertEqual(rows.first?.state, .idle)
    }

    func test_favoriteRows_orderedByServerDisplayNameThenPort() {
        let vm = makeViewModel()
        let alpha = Server(name: "alpha", user: "u", host: "a")
        let beta = Server(name: "beta", user: "u", host: "b")
        vm.addServer(beta)
        vm.addServer(alpha)
        vm.toggleFavorite(serverId: beta.id, port: 6379)
        vm.toggleFavorite(serverId: alpha.id, port: 5432)
        vm.toggleFavorite(serverId: alpha.id, port: 5433)

        let names = vm.favoriteRows.map(\.serverDisplayName)
        let ports = vm.favoriteRows.map(\.remotePort)
        XCTAssertEqual(names, ["alpha (a)", "alpha (a)", "beta (b)"])
        XCTAssertEqual(ports, [5432, 5433, 6379])
    }

    func test_favoriteRows_orphanedFavorite_excluded() {
        let vm = makeViewModel()
        let ghostServerId = UUID()
        vm.toggleFavorite(serverId: ghostServerId, port: 5432)
        // 서버가 ServerStore에 없으면 표시되지 않음
        XCTAssertTrue(vm.favoriteRows.isEmpty)
    }

    func test_nonFavoriteActive_emptyWhenAllActiveAreFavorites() {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 80)
        // 활성 포워딩 직접 주입 (테스트 헬퍼 — Task 5 끝에서 정의)
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 80)
        XCTAssertTrue(vm.nonFavoriteActive.isEmpty)
    }

    func test_nonFavoriteActive_includesNonFavoriteActive() {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm._test_injectActiveForwarding(serverId: s.id, remotePort: 9000)
        let active = vm.nonFavoriteActive
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.remotePort, 9000)
    }
```

- [ ] **Step 2: 테스트 빌드 실패 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build-for-testing -quiet 2>&1 | tail -10
```

기대: `Value of type 'AppViewModel' has no member 'favoriteRows'` 등.

- [ ] **Step 3: 구현 — `FavoriteRow` struct + 계산 속성 + 테스트 헬퍼**

`PortBridge/ViewModels/AppViewModel.swift` 파일 끝(기존 `extension AppViewModel: TunnelManagerDelegate` 뒤)에 다음 추가:

```swift
struct FavoriteRow: Identifiable, Equatable {
    let id: FavoriteKey
    let serverDisplayName: String
    let remotePort: Int
    let localPort: Int?
    let processName: String?
    let state: Forwarding.State
}
```

`AppViewModel` 본체 안의 `// MARK: - Favorites` 섹션 끝에 추가:

```swift
    var favoriteRows: [FavoriteRow] {
        favorites.favorites.compactMap { key -> FavoriteRow? in
            guard let server = store.servers.first(where: { $0.id == key.serverId }) else {
                return nil
            }
            let forwarding = forwardings.first(where: {
                $0.serverId == key.serverId && $0.remotePort == key.remotePort
            })
            let section = serverSections.first(where: { $0.server.id == key.serverId })
            let processName = section?.ports.first(where: { $0.port == key.remotePort })?.processName
            return FavoriteRow(
                id: key,
                serverDisplayName: server.displayName,
                remotePort: key.remotePort,
                localPort: forwarding?.localPort,
                processName: processName,
                state: forwarding?.state ?? .idle
            )
        }
        .sorted { lhs, rhs in
            if lhs.serverDisplayName == rhs.serverDisplayName {
                return lhs.remotePort < rhs.remotePort
            }
            return lhs.serverDisplayName < rhs.serverDisplayName
        }
    }

    var nonFavoriteActive: [Forwarding] {
        activeForwardings.filter { fw in
            !isFavorite(serverId: fw.serverId, port: fw.remotePort)
        }
    }
```

테스트 헬퍼 (파일 끝, `FavoriteRow` 정의 아래):

```swift
#if DEBUG
extension AppViewModel {
    /// 테스트 전용 — 활성 포워딩 상태를 임의로 주입.
    func _test_injectActiveForwarding(serverId: UUID, remotePort: Int, localPort: Int? = nil) {
        let fw = Forwarding(
            serverId: serverId,
            remotePort: remotePort,
            localPort: localPort ?? remotePort,
            state: .active,
            activatedAt: Date()
        )
        forwardings.append(fw)
    }
}
#endif
```

`forwardings`는 `private(set)`이라 같은 모듈 내 extension에서 쓰기 가능 — 테스트 타겟은 `@testable import` 사용 중이므로 접근 가능.

- [ ] **Step 4: 테스트 실행 — Xcode GUI**

⌘U → 새 테스트 6개 ✓, 기존 테스트도 ✓ 유지.

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelFavoritesTests.swift
git commit -m "feat(viewmodel): add favoriteRows and nonFavoriteActive computed properties"
```

---

## Task 6: `AppViewModel.startFavoritesIfEnabled()`

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Modify: `PortBridgeTests/AppViewModelFavoritesTests.swift` (추가 테스트)

- [ ] **Step 1: 실패하는 테스트 추가**

`PortBridgeTests/AppViewModelFavoritesTests.swift` 끝에 추가:

```swift
    func test_startFavoritesIfEnabled_skipsWhenLaunchAtLoginOff() async {
        let vm = makeViewModel()
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 5432)
        // launchAtLogin은 기본 false
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        XCTAssertTrue(vm.activeForwardings.isEmpty)
    }

    func test_startFavoritesIfEnabled_startsFavoritesWhenEnabled() async {
        let vm = makeViewModel()
        vm.preferences.launchAtLogin = true
        let s = Server(name: "x", user: "u", host: "h")
        vm.addServer(s)
        vm.toggleFavorite(serverId: s.id, port: 5432)
        vm.toggleFavorite(serverId: s.id, port: 6379)
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        // MockTunnelManager는 시작을 즉시 active로 만든다
        XCTAssertEqual(vm.activeForwardings.count, 2)
    }

    func test_startFavoritesIfEnabled_skipsOrphanedFavorites() async {
        let vm = makeViewModel()
        vm.preferences.launchAtLogin = true
        let ghostServerId = UUID()
        vm.toggleFavorite(serverId: ghostServerId, port: 5432)
        await vm.startFavoritesIfEnabled(graceSeconds: 0)
        XCTAssertTrue(vm.activeForwardings.isEmpty)
    }
```

**MockTunnelManager 확인** — `PortBridgeTests/MockTunnelManager.swift`가 `start(...)`를 호출 시 `Forwarding`을 `.active` 상태로 반환하는지 확인. 만약 다르게 동작하면 위 테스트가 실패할 수 있음.

- [ ] **Step 2: MockTunnelManager 검토**

```bash
cat PortBridgeTests/MockTunnelManager.swift
```

`start(server:remotePort:localPort:)`가 `.active` Forwarding을 반환하는지 검증. 만약 다른 동작이면 plan 작성 시점에서 알려진 동작에 맞춰 테스트 기댓값 조정 — 예를 들어 `.starting`만 반환한다면 `activeForwardings`는 `.starting`도 포함하므로 카운트가 동일.

`activeForwardings` 정의 ([AppViewModel.swift:71](PortBridge/ViewModels/AppViewModel.swift)):

```swift
.filter { fw in
    switch fw.state {
    case .active, .starting, .error: return true
    case .idle: return false
    }
}
```

→ `.active`/`.starting`/`.error` 모두 포함이므로 위 테스트는 Mock 구현과 무관하게 통과해야 함.

- [ ] **Step 3: 테스트 빌드 실패 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build-for-testing -quiet 2>&1 | tail -10
```

기대: `Value of type 'AppViewModel' has no member 'startFavoritesIfEnabled'`.

- [ ] **Step 4: 구현**

`PortBridge/ViewModels/AppViewModel.swift`의 `// MARK: - Favorites` 섹션 끝에 추가:

```swift
    /// 앱 시작 시 호출 — preferences.launchAtLogin이 true이면 즐겨찾기를 자동 시작.
    /// `graceSeconds`는 부팅 후 VPN/네트워크 안정화 대기 (production: 5초, 테스트: 0).
    func startFavoritesIfEnabled(graceSeconds: TimeInterval = 5) async {
        guard preferences.launchAtLogin else { return }
        if graceSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(graceSeconds * 1_000_000_000))
        }
        await withTaskGroup(of: Void.self) { group in
            for key in favorites.favorites {
                guard let section = serverSections.first(where: { $0.server.id == key.serverId }) else {
                    continue
                }
                let server = section.server
                let port = key.remotePort
                group.addTask { @MainActor in
                    await self.startForwarding(server: server, remotePort: port, localPort: port)
                }
            }
        }
    }
```

`startForwarding`은 기존에 `private`이므로 internal로 노출하거나 동일 파일에서 호출하므로 그대로 사용 가능. 위 코드는 same-file 호출이라 private 그대로 OK.

- [ ] **Step 5: 테스트 실행 — Xcode GUI**

⌘U → 새 3개 테스트 ✓.

- [ ] **Step 6: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelFavoritesTests.swift
git commit -m "feat(viewmodel): add startFavoritesIfEnabled with grace period"
```

---

## Task 7: `ForwardingRowView` — leading 별 버튼

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift`
- Modify: `PortBridge/Views/ServerSectionView.swift` (호출 사이트)

SwiftUI 뷰는 단위 테스트가 제한적 — Xcode Preview + 수동 검증으로 대체. 테스트는 ViewModel 레이어에서 이미 검증됨.

- [ ] **Step 1: `ForwardingRowView` 시그니처 확장**

`PortBridge/Views/ForwardingRowView.swift`의 struct property 부분을 다음으로 교체:

```swift
struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let serverDisplayName: String?
    let isFavorite: Bool
    let onToggle: () -> Void
    let onFavoriteToggle: () -> Void
```

`body` 안의 `HStack(alignment: .center, spacing: 10) { ... }` 첫 자식으로 별 버튼 삽입 — 기존 `statusIndicator` 앞:

```swift
        HStack(alignment: .center, spacing: 10) {
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가")
            .help(isFavorite ? "즐겨찾기에서 제거" : "즐겨찾기에 추가")

            statusIndicator
                .frame(width: 18, height: 18)
            // ... 기존 코드 ...
```

기존 `#Preview` 4개를 다음 패턴으로 모두 수정 — 인자 2개 추가:

```swift
#Preview("Idle · 비활성 포트") {
    ForwardingRowView(
        port: RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx"),
        forwarding: nil,
        serverDisplayName: nil,
        isFavorite: false,
        onToggle: {},
        onFavoriteToggle: {}
    )
    .padding()
    .frame(width: 420)
}
```

나머지 3개 Preview도 동일하게 `isFavorite: false`, `onFavoriteToggle: {}` 추가. (Active용 하나는 `isFavorite: true`로 채워 차이를 보이게 함.)

- [ ] **Step 2: `ServerSectionView` 호출 사이트 수정**

`ServerSectionView`는 현재 `viewModel`을 직접 받지 않고 클로저(`onToggle`)를 받는 패턴이다. 동일 패턴을 따라 `isFavorite`/`onFavoriteToggle`도 외부에서 주입.

`PortBridge/Views/ServerSectionView.swift:5-11`의 stored property 부분 교체:

```swift
struct ServerSectionView: View {
    let section: ServerSectionViewModel
    let activeForwardings: [Forwarding]
    let matches: (RemotePort) -> Bool
    let onToggle: (RemotePort) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let isFavorite: (RemotePort) -> Bool
    let onFavoriteToggle: (RemotePort) -> Void
```

`PortBridge/Views/ServerSectionView.swift:71`의 ForwardingRowView 호출을 다음으로 교체:

```swift
                ForwardingRowView(
                    port: port,
                    forwarding: nil,
                    serverDisplayName: nil,
                    isFavorite: isFavorite(port),
                    onToggle: { onToggle(port) },
                    onFavoriteToggle: { onFavoriteToggle(port) }
                )
```

- [ ] **Step 3: `ServerListView` 호출 사이트 수정**

`ServerListView`에는 두 곳 수정이 필요하다.

(a) `ServerSectionView(...)` 호출 — 새 클로저 두 개 전달. 호출 컨텍스트를 파일에서 확인 후 다음 두 인자 추가:

```swift
                    isFavorite: { port in vm.isFavorite(serverId: section.server.id, port: port.port) },
                    onFavoriteToggle: { port in vm.toggleFavorite(serverId: section.server.id, port: port.port) }
```

(b) `PortBridge/Views/ServerListView.swift:172-178`의 `activeRow` 안 ForwardingRowView 호출을 다음으로 교체:

```swift
            ForwardingRowView(
                port: port,
                forwarding: fw,
                serverDisplayName: vm.serverDisplayName(for: fw.serverId),
                isFavorite: vm.isFavorite(serverId: fw.serverId, port: port.port),
                onToggle: { Task { await vm.toggleForwarding(serverId: fw.serverId, for: port) } },
                onFavoriteToggle: { vm.toggleFavorite(serverId: fw.serverId, port: port.port) }
            )
```

- [ ] **Step 4: 빌드 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build -quiet 2>&1 | tail -5
```

기대: `BUILD SUCCEEDED`.

- [ ] **Step 5: Xcode Preview / 실행 시각 검증**

Xcode → ⌘R로 앱 실행 → 서버 추가 후 포트 행에 ☆ 표시 확인 → 클릭 → ★로 변경 확인 → 다시 클릭 → ☆로 복귀.

- [ ] **Step 6: 커밋**

```bash
git add PortBridge/Views/ForwardingRowView.swift PortBridge/Views/ServerSectionView.swift PortBridge/Views/ServerListView.swift
git commit -m "feat(view): add leading star button to ForwardingRowView for favorites toggle"
```

---

## Task 8: `MenuBarContent` 뷰

**Files:**
- Create: `PortBridge/Views/MenuBarContent.swift`

- [ ] **Step 1: 파일 생성**

`PortBridge/Views/MenuBarContent.swift`:

```swift
import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var prefs = viewModel.preferences

        Group {
            favoritesSection

            if !viewModel.nonFavoriteActive.isEmpty {
                Divider()
                activeSection
            }

            if !viewModel.errors.isEmpty {
                Divider()
                errorSummary
            }

            Divider()

            Button("Open Main Window") { activateMainWindow() }
                .keyboardShortcut("o", modifiers: [.command])

            Toggle("Launch at Login", isOn: $prefs.launchAtLogin)
            Toggle("Show in Dock", isOn: $prefs.showInDock)

            Divider()

            Button("Quit PortBridge") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var favoritesSection: some View {
        let rows = viewModel.favoriteRows
        Text("Favorites").font(.caption).foregroundStyle(.secondary)
        if rows.isEmpty {
            Text("메인 창에서 ★를 눌러 즐겨찾기를 추가하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        } else {
            ForEach(rows) { row in
                Button(action: { toggle(row) }) {
                    favoriteLabel(row: row)
                }
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        Text("Active").font(.caption).foregroundStyle(.secondary)
        ForEach(viewModel.nonFavoriteActive) { fw in
            Button(action: { stopForwarding(fw) }) {
                Text(":\(fw.remotePort)").monospaced()
            }
        }
    }

    @ViewBuilder
    private var errorSummary: some View {
        let count = viewModel.errors.count
        Button(action: { activateMainWindow() }) {
            Label("\(count) error\(count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Labels

    private func favoriteLabel(row: FavoriteRow) -> some View {
        let host = row.serverDisplayName
        let portText = ":\(row.remotePort)"
        let proc = row.processName.map { " \($0)" } ?? ""
        let dot = isActive(state: row.state) ? "● " : "○ "
        return Text("\(dot)\(host)\(portText)\(proc)")
            .monospaced()
    }

    private func isActive(state: Forwarding.State) -> Bool {
        switch state {
        case .active, .starting: return true
        case .idle, .error: return false
        }
    }

    // MARK: - Actions

    private func toggle(_ row: FavoriteRow) {
        Task {
            // 동일 (serverId, remotePort)로 toggleForwarding 호출 — RemotePort 객체가 필요
            // 메뉴바에서는 RemotePort.processName이 nil일 수 있어 임시 객체 사용
            let port = RemotePort(port: row.remotePort, address: "0.0.0.0", processName: row.processName)
            await viewModel.toggleForwarding(serverId: row.id.serverId, for: port)
        }
    }

    private func stopForwarding(_ fw: Forwarding) {
        Task {
            let port = RemotePort(port: fw.remotePort, address: "0.0.0.0", processName: nil)
            await viewModel.toggleForwarding(serverId: fw.serverId, for: port)
        }
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
```

- [ ] **Step 2: Xcode 등록**

`PortBridge/Views` 그룹에 추가. Target Membership = **PortBridge**만.

- [ ] **Step 3: 빌드 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build -quiet 2>&1 | tail -10
```

기대: `BUILD SUCCEEDED`. (앞으로 Task 9에서 Scene에 wire-up.)

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Views/MenuBarContent.swift PortBridge.xcodeproj/project.pbxproj
git commit -m "feat(view): add MenuBarContent (favorites, active, errors, prefs)"
```

---

## Task 9: `PortBridgeApp` — MenuBarExtra Scene + activation policy + 자동 시작

**Files:**
- Modify: `PortBridge/PortBridgeApp.swift`

- [ ] **Step 1: `PortBridgeApp.swift` 수정**

기존 `PortBridge/PortBridgeApp.swift` 전체를 다음으로 교체:

```swift
import SwiftUI
import AppKit

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(delegate.viewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(delegate.viewModel)
        } label: {
            Image(systemName: menuBarSymbol(for: delegate.viewModel))
        }
        .menuBarExtraStyle(.menu)
    }

    private func menuBarSymbol(for vm: AppViewModel) -> String {
        if !vm.errors.isEmpty { return "arrow.triangle.swap.exclamationmark" }
        if vm.activeForwardings.isEmpty { return "arrow.triangle.swap" }
        return "arrow.triangle.swap"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel

    override init() {
        if !Self.isRunningUnderTest {
            AppSingleInstance.exitIfAnotherInstanceIsRunning()
            TunnelManager.cleanupOrphanedTunnels()
        }
        self.viewModel = AppViewModel()
        super.init()
        AppSingleInstance.startActivationObserver()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 영속화된 사용자 선택을 깜빡임 없이 즉시 반영
        NSApp.setActivationPolicy(viewModel.preferences.showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 즐겨찾기 자동 시작 — launchAtLogin이 켜져 있을 때만
        Task { @MainActor in
            await viewModel.startFavoritesIfEnabled()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !AppSingleInstance.activateCurrentInstance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel.shutdownAll()
        }
        AppSingleInstance.stop()
    }

    private static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-UITesting")
    }
}
```

**참고 — 메뉴바 아이콘 심볼**: spec에는 `arrow.triangle.swap` 단일 사용 + 에러 시 변형으로 명시. 위 코드는 명료성을 위해 단일 심볼로 시작하고 추후 에러 변형(`exclamationmark` 오버레이) 적용은 후속 작업으로 둔다.

- [ ] **Step 2: WindowGroup id 매칭 확인**

위 코드에서 `WindowGroup(id: "main")`로 명명했고, `MenuBarContent.openWindow(id: "main")`가 이를 호출한다. id가 일치해야 함.

- [ ] **Step 3: 빌드 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build -quiet 2>&1 | tail -10
```

기대: `BUILD SUCCEEDED`.

- [ ] **Step 4: Xcode GUI 전체 테스트**

⌘U → 모든 기존 테스트 + 신규 테스트 ✓.

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/PortBridgeApp.swift
git commit -m "feat(app): add MenuBarExtra Scene, activation policy init, favorites autostart"
```

---

## Task 10: 수동 검증 시나리오

**Files:** 없음 (검증 단계)

- [ ] **Step 1: 앱 실행**

Xcode → ⌘R.

- [ ] **Step 2: 즐겨찾기 0개 — empty state 확인**

- 메뉴바 아이콘 클릭 → "Favorites" 헤더 아래 "메인 창에서 ★를 눌러 즐겨찾기를 추가하세요" 텍스트 표시.
- "Open Main Window" 클릭 → 메인 창 열림.

- [ ] **Step 3: 즐겨찾기 등록**

- 메인 창에서 서버 추가 → 스캔 완료 후 포트 행에 ☆ 표시.
- ☆ 클릭 → ★로 전환, 색 accent.
- 메뉴바 다시 열기 → Favorites 섹션에 항목 1개 표시 (`host:port  processName`).

- [ ] **Step 4: 메뉴바에서 토글**

- Favorites 항목 클릭 → 메뉴 닫힘 → 다시 열어 보면 `● host:port` (활성 dot)으로 변경.
- 메인 창의 같은 행도 토글 스위치 ON 상태 동기화 확인.

- [ ] **Step 5: Active (non-favorite) 섹션**

- 메인 창에서 즐겨찾기 아닌 다른 포트 행 토글 ON.
- 메뉴바 → "Active" 섹션이 새로 나타나고 해당 항목 표시.
- 토글 OFF 후 메뉴바 다시 열기 → "Active" 섹션 사라짐.

- [ ] **Step 6: Show in Dock 토글**

- 메뉴바 → "Show in Dock" 체크 해제 → Dock 아이콘 즉시 사라짐. 메인 창은 그대로 유지.
- 메인 창 닫음 → 앱 살아있음 (메뉴바 아이콘 그대로).
- 메뉴바 → "Open Main Window" → 메인 창 다시 열림.
- "Show in Dock" 재체크 → Dock 아이콘 즉시 복귀.

- [ ] **Step 7: Launch at Login 토글**

- 메뉴바 → "Launch at Login" 체크 → System Settings → General → Login Items 열기 → PortBridge 항목이 enabled로 표시되는지 확인.
- 토글 해제 → System Settings에서도 disabled로 동기화.

- [ ] **Step 8: 자동 시작 시뮬레이션**

- 즐겨찾기 2개 등록된 상태에서 Launch at Login ON 유지.
- 앱 종료 후 다시 실행 (⌘R).
- 5초 대기 후 메뉴바 → Favorites 항목들이 자동으로 활성(●) 상태가 되는지 확인.

- [ ] **Step 9: 에러 요약**

- 의도적으로 잘못된 호스트 추가 (예: `user@invalid.example.com`).
- 즐겨찾기 등록 후 토글 시도 → 실패 → 메뉴바에 "⚠︎ N error" 행 등장.
- 메뉴바 에러 행 클릭 → 메인 창 활성화.

- [ ] **Step 10: 마지막 빌드/테스트 확인**

```bash
xcodebuild -scheme PortBridge -configuration Debug build -quiet 2>&1 | tail -5
```

기대: `BUILD SUCCEEDED`.

Xcode GUI → ⌘U → 전체 그린.

- [ ] **Step 11: 최종 커밋 (있다면)**

수동 검증 중 발견된 작은 버그가 있으면 fix 커밋. 없으면 이 단계는 건너뜀.

```bash
git status
# 변경 사항이 있을 경우만:
git add .
git commit -m "fix: <발견된 이슈 요약>"
```

---

## Self-Review 메모

스펙 대비 커버리지:
- §3.1 즐겨찾기 자동 시작 모델 → Task 6
- §3.2 별 시각화 → Task 7
- §3.3 Dock 정책 토글 → Task 3 (AppPreferences), Task 8 (UI), Task 9 (초기 적용)
- §3.4 인라인 환경설정 → Task 8 (별도 Preferences 모달 부재)
- §4 데이터 모델 → Task 1, 2, 3
- §5 AppViewModel 확장 → Task 4, 5, 6
- §6 UI 변경 → Task 7, 8
- §7 앱 시작 시 동작 → Task 9, Task 6
- §8 Dock 정책 전환 → Task 3 + Task 9
- §10 테스트 전략 → 각 Task의 테스트 step

알려진 후속 작업 (이 plan 범위 외):
- 메뉴바 아이콘 에러 변형 (spec §6.4 "exclamationmark 오버레이") — 단일 심볼로 시작, 사용자 피드백 후 정교화.
- ⌥-클릭 편의 단축 — SwiftUI MenuBarExtra `.menu` 스타일에서는 modifier 감지가 제한적. `.window` 스타일 도입 시점에 재검토.
