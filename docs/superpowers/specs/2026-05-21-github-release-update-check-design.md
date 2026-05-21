# GitHub Release 기반 업데이트 체크 — 설계 (Phase 1)

- **작성일**: 2026-05-21
- **상태**: 승인됨 (구현 대기)
- **대상 버전**: PortBridge v0.2.0
- **관련 파일**: `.github/workflows/release.yml`, `install-release.sh`, `PortBridge/MenuBarController.swift`, `PortBridge/Storage/AppPreferences.swift`, `PortBridge/Views/MenuBarIconView.swift`, `PortBridge/PortBridgeApp.swift`, `PortBridge/ViewModels/AppViewModel.swift`

## 1. 목표 및 비목표

### 목표
사용자가 PortBridge의 새 안정 버전이 GitHub Release로 게시되었음을 인지하고, 한 번의 클릭으로 release 페이지에 도달하도록 한다.

### 비목표
- 앱 내 in-place 자동 교체 (Sparkle 영역, Phase 2 이후)
- Pre-release/베타 채널 알림
- Delta 업데이트
- 사용 통계, 텔레메트리 수집

## 2. 핵심 결정 사항 (확정)

| 결정 | 선택 | 근거 |
|---|---|---|
| 아키텍처 | 별도 `@Observable UpdateChecker` + `ReleaseFetcher` 프로토콜 | 코드베이스의 책임 분리 패턴(`TunnelManager`, `PortScanner`)과 일관, 테스트 격리 |
| UX 채널 | 메뉴바 아이콘 배지 + 메뉴 항목 + 첫 감지 시 시스템 배너 1회 | 메뉴바 앱 관행 (Tailscale/NetBird), 비방해 |
| 배지 색상 | `NSColor.systemBlue` | macOS 시스템 컨벤션상 "정보성", 에러 표시(빨강)와 충돌 없음 |
| 클릭 동작 | `NSWorkspace.shared.open(release.htmlURL)` | 기존 `install-release.sh` 경로 재사용, 단순성 |
| Skip This Version | 제공. 더 높은 버전 출시 시 자동 재알림 | 사용자 자율성, Sparkle 표준 패턴 |
| Pre-release 처리 | 무시 (`/releases/latest` API만 사용) | API가 stable만 반환, 코드 단순 |
| 자동 체크 토글 | 제공 (기본 ON) | 회사 보안 정책 등 외부 통신 차단 사용자 배려 |
| 에러 UX | 자동=조용히 로그, 수동="Check failed — try again" | 사용자 요청 여부에 따른 차등 |
| 체크 시점 | 앱 시작 시 + 메뉴 "Check Now" 수동 + 24h debounce | 발견성과 비방해의 균형 |
| 버전 정렬 | CI에서 태그 → `MARKETING_VERSION` 자동 주입 | 수동 동기화는 반드시 잊혀짐 |

## 3. 컴포넌트 구조

```
PortBridge/
├── Updates/                              ← 신규 폴더
│   ├── UpdateChecker.swift               ← @Observable, MainActor, 상태 + 조정
│   ├── ReleaseFetcher.swift              ← protocol + GitHubReleaseFetcher 구현체
│   ├── ReleaseInfo.swift                 ← 모델 (tagName, htmlURL, name, body)
│   ├── SemanticVersion.swift             ← 파싱/비교 (Comparable 값 타입)
│   └── UpdateNotifier.swift              ← UNUserNotification wrapper (첫 감지 1회)
├── Views/
│   └── MenuBarIconView.swift             ← 수정 없음 (배지는 status item button에 CALayer로 별도 합성)
├── MenuBarController.swift               ← 수정: 메뉴 항목 + 배지 레이어 관리
├── PortBridgeApp.swift                   ← 수정: AppDelegate에서 UpdateChecker 생성/주입
├── ViewModels/AppViewModel.swift         ← 수정: let updates: UpdateChecker 보유
└── Storage/AppPreferences.swift          ← 수정: var automaticUpdateCheckEnabled: Bool 추가
```

**책임 분리**:
- **`ReleaseFetcher`**: HTTP만. GitHub `/releases/latest` 호출 → `ReleaseInfo` 또는 throw. 테스트 시 Mock 주입.
- **`SemanticVersion`**: 순수 값 타입. `init?(string:)` 파싱, `Comparable`. 단독 테스트.
- **`UpdateChecker`**: 조정자. `checkIfDue()`, `checkNow()`, `skipCurrent()`, `phase` 발행. `lastCheckedAt`/`skippedVersion`/`lastNotifiedVersion`을 `UserDefaults`에 영속화 (의존성 주입).
- **`UpdateNotifier`**: `UNUserNotificationCenter` 권한 요청 + 1회 표시. 재진입 방지 로직은 `UpdateChecker`에서 (`lastNotifiedVersion` 비교).
- **`AppPreferences`**: `automaticUpdateCheckEnabled: Bool` (기본 true). UpdateChecker가 이 값을 읽어 자동 체크 여부 결정.

## 4. 상태 모델 & 데이터 플로우

### UpdateChecker.Phase

```swift
@MainActor @Observable
final class UpdateChecker {
    enum Phase {
        case idle                       // 초기 / 결과 없음
        case checking                   // 진행 중
        case upToDate(checkedAt: Date)  // 최신
        case available(ReleaseInfo)     // 새 버전 있음 (skipped 아님)
        case failed(checkedAt: Date)    // 마지막 시도 실패
    }
    var phase: Phase = .idle

    // 영속 (UserDefaults)
    private(set) var lastCheckedAt: Date?
    private(set) var skippedVersion: SemanticVersion?
    private(set) var lastNotifiedVersion: SemanticVersion?

    // 파생 (View가 읽음)
    var availableUpdate: ReleaseInfo? {
        if case .available(let info) = phase { return info }
        return nil
    }
}
```

**Phase enum의 의의**: 한 시점에 한 케이스만 가능 → invalid state 방지 (예: checking이면서 동시에 available일 수 없음).

### 데이터 플로우

```
[App launch]
  └─ AppDelegate.applicationDidFinishLaunching
       └─ updates.checkIfDue()   ← preferences.automaticUpdateCheckEnabled && 24h debounce
            └─ phase = .checking
                 └─ ReleaseFetcher.fetchLatest()
                      ├─ success(release) ─┐
                      │                     └─ compare(currentVersion, release.tag)
                      │                          ├─ newer & !skipped → phase = .available
                      │                          │       └─ if lastNotifiedVersion != release.version:
                      │                          │            UpdateNotifier.notify(release)
                      │                          │            lastNotifiedVersion = release.version
                      │                          └─ else → phase = .upToDate
                      └─ failure ─────────→ phase = .failed (자동 체크면 silent)

[User clicks "Check Now" in menu]
  └─ updates.checkNow()  ← debounce 무시, 강제. preferences 토글도 무시.
       └─ (위와 동일 플로우, 실패 시 메뉴 텍스트로 표시)

[User clicks "Update available v0.2.0..." in menu]
  └─ NSWorkspace.shared.open(release.htmlURL)

[User clicks "Skip This Version"]
  └─ updates.skipCurrent()
       ├─ skippedVersion = release.version  (UserDefaults persist)
       └─ phase = .upToDate (시각적으로 즉시 배지/항목 사라짐)

[User toggles "Check for Updates Automatically" off]
  └─ preferences.automaticUpdateCheckEnabled = false
       └─ launch 자동 체크 차단. 수동 "Check Now"는 여전히 동작.
```

### 두 종류의 "기억" — `skippedVersion` vs `lastNotifiedVersion`

| | 의미 | 영향 |
|---|---|---|
| `skippedVersion` | 사용자가 명시적으로 "이 버전 건너뜀" 선택 | 도트/메뉴 항목/배너 **모두** 표시 안 함 |
| `lastNotifiedVersion` | 배너가 이미 표시된 버전 (중복 방지) | **배너만** 스킵, 도트/메뉴는 계속 표시 |

더 높은 버전(예: 0.3.0)이 나오면 두 값 모두 무력화되어 정상 알림.

### 24h debounce

```swift
func checkIfDue() async {
    guard preferences.automaticUpdateCheckEnabled else { return }
    if let last = lastCheckedAt, Date().timeIntervalSince(last) < 86_400 { return }
    await checkNow()
}
```

## 5. HTTP, 에러 처리, 버전 정렬

### ReleaseFetcher 프로토콜

```swift
protocol ReleaseFetcher: Sendable {
    func fetchLatest() async throws -> ReleaseInfo
}

struct GitHubReleaseFetcher: ReleaseFetcher {
    let owner: String   // "yhzion"
    let repo: String    // "PortBridge"
    let session: URLSession
    let currentAppVersion: String  // User-Agent용

    func fetchLatest() async throws -> ReleaseInfo { ... }
}
```

### HTTP 요청 세부

- **Endpoint**: `https://api.github.com/repos/yhzion/PortBridge/releases/latest`
- **Headers**:
  - `Accept: application/vnd.github+json`
  - `X-GitHub-Api-Version: 2022-11-28`
  - `User-Agent: PortBridge/<버전>` (GitHub API 요구; 누락 시 403)
- **Timeout**: 10초
- **인증 없음**: 60 req/h/IP. launch + 24h debounce + 수동만이라 사실상 안전.

### ReleaseInfo

```swift
struct ReleaseInfo: Sendable, Decodable {
    let tagName: String          // "v0.2.0"
    let name: String?            // 사람이 정한 제목 (없을 수 있음)
    let htmlURL: URL             // 브라우저로 열 페이지
    let publishedAt: Date?
    let body: String?            // release notes (미래 확장 대비)

    var version: SemanticVersion? { SemanticVersion(string: tagName) }
}
```

JSONDecoder는 `keyDecodingStrategy = .convertFromSnakeCase` + `dateDecodingStrategy = .iso8601`.

### 에러 분류

```swift
enum UpdateCheckError: Error {
    case network(URLError)       // 오프라인, 타임아웃, DNS
    case httpStatus(Int)         // 4xx, 5xx (rate limit 403 포함)
    case decoding(Error)         // JSON 파싱 실패 (스키마 변경)
    case invalidTag(String)      // tag_name이 SemVer 아님
}
```

- **자동 체크 실패**: `phase = .failed(checkedAt: now)`, `os_log` 경고. 메뉴에 표시 안 함.
- **수동 체크 실패**: 동일 + "Check for Updates Now…" 라벨을 잠시 "Check failed — try again"으로 (다음 메뉴 열림 시 원복).

### SemanticVersion

```swift
struct SemanticVersion: Comparable, Sendable, Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(string: String) {
        // "v0.2.0" → "0.2.0" (v 접두사 허용)
        // "0.2.0" → [0,2,0]
        // "0.2" → [0,2,0] (patch 누락 시 0 보충)
        // "v1.0.0-beta.1" → nil (pre-release 거부)
        // "abc", "" → nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool { ... }  // tuple 비교
}

extension Bundle {
    var currentVersion: SemanticVersion? {
        guard let s = infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return SemanticVersion(string: s)
    }
}
```

**비교 안전장치**: 현재 앱 버전 파싱이 실패하면 안전하게 "업데이트 없음"으로 간주 + `os_log` 경고. 사용자에게 가짜 알림보다 안전.

## 6. UI 디테일

### 메뉴 구성 (`MenuBarController.buildMenu()`)

```
┌─────────────────────────────────────────┐
│ ⓘ Update available — v0.2.0            │ ← phase == .available 일 때만
│      Skip This Version                 │   서브메뉴
│      Show Release Notes…               │
├─────────────────────────────────────────┤
│ Favorites                              │ ← 기존
│   ● server-a:8080                      │
│   ○ server-b:5432                      │
│ (… Active / Errors 섹션 기존 유지 …)   │
├─────────────────────────────────────────┤
│ Open Main Window               ⌘O      │ ← 기존
│ Launch at Login                ✓       │ ← 기존
│ Show in Dock                   ✓       │ ← 기존
│ Check for Updates Automatically ✓      │ ← 신규
│ Check for Updates Now…                 │ ← 신규
├─────────────────────────────────────────┤
│ Quit PortBridge                ⌘Q      │ ← 기존
└─────────────────────────────────────────┘
```

**동작**:
- "Update available" 메인 항목 클릭 → `NSWorkspace.shared.open(release.htmlURL)`
- 서브 "Skip This Version" → `updates.skipCurrent()`
- 서브 "Show Release Notes…" → 메인 항목과 동일 (라벨로 발견성↑)
- "Check for Updates Now…" → `updates.checkNow()`, 결과에 따라 다음 메뉴 열림 시 갱신
- "Check for Updates Automatically" → `preferences.automaticUpdateCheckEnabled.toggle()`

### 메뉴바 아이콘 배지 — CALayer 합성

**제약**: `MenuBarIconRenderer`는 `isTemplate = true` (자동 다크/라이트 tinting). 컬러 도트를 동일 이미지에 그리면 tinting으로 색이 사라짐.

**해법**: status item button에 별도 CALayer 추가.

```swift
private var badgeLayer: CALayer?

func updateBadge(visible: Bool) {
    guard let button = statusItem?.button else { return }
    if visible {
        if badgeLayer == nil {
            let layer = CALayer()
            layer.backgroundColor = NSColor.systemBlue.cgColor
            layer.cornerRadius = 2
            button.wantsLayer = true
            button.layer?.addSublayer(layer)
            badgeLayer = layer
        }
        layoutBadge()  // 4×4pt, button bounds 우상단
    } else {
        badgeLayer?.removeFromSuperlayer()
        badgeLayer = nil
    }
}
```

- 아이콘 본체는 template image 유지 (시스템 tinting 그대로)
- 배지는 별도 레이어로 `systemBlue` 색상 유지
- `NSColor.systemBlue.cgColor`는 dark/light mode 자동 적응

**Observation 재-arm 패턴** (기존 `observeIconState()` 확장):

```swift
private func observeIconState() {
    withObservationTracking {
        _ = viewModel.isAnyFavoriteActive
        _ = viewModel.updates.availableUpdate
    } onChange: { [weak self] in
        Task { @MainActor in
            self?.refreshIcon()
            self?.updateBadge(visible: self?.viewModel.updates.availableUpdate != nil)
            self?.observeIconState()  // re-arm
        }
    }
}
```

### AppPreferences 확장

```swift
var automaticUpdateCheckEnabled: Bool {
    didSet {
        guard !suppressApply, automaticUpdateCheckEnabled != oldValue else { return }
        defaults.set(automaticUpdateCheckEnabled, forKey: automaticUpdateCheckEnabledKey)
    }
}
private let automaticUpdateCheckEnabledKey = "PortBridge.AutomaticUpdateCheckEnabled"
// 기본값: true (첫 실행 시 defaults.object(forKey:) == nil 일 때)
```

`launchAtLogin`/`showInDock`와 달리 시스템 API 적용이 없으므로 `apply*` 클로저 불필요.

## 7. CI: 태그 → MARKETING_VERSION 자동 주입

`.github/workflows/release.yml`의 Build step:

```yaml
- name: Build Release app
  run: |
    set -euo pipefail
    # refs/tags/v0.2.0 → 0.2.0
    VERSION="${GITHUB_REF_NAME#v}"
    xcodebuild \
      -project PortBridge.xcodeproj \
      -scheme PortBridge \
      -configuration Release \
      -derivedDataPath build/Release \
      CODE_SIGNING_ALLOWED=NO \
      MARKETING_VERSION="$VERSION" \
      CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}" \
      clean build
```

- `MARKETING_VERSION`: 태그에서 `v` 제거 → `CFBundleShortVersionString` 반영
- `CURRENT_PROJECT_VERSION`: GitHub Actions run number (단조 증가) → 미래 hot-fix 재빌드에도 안전
- pbxproj의 `MARKETING_VERSION = 1.0`은 로컬 개발용 기본값으로 유지. **단, Step 4에서 `0.1.0`으로 정렬하여 첫 정식 릴리스와 일치시킴**
- `workflow_dispatch`로 태그 없이 수동 실행 시 `VERSION=main`이 되지만 release upload step이 `if: startsWith(github.ref, 'refs/tags/')`로 차단되므로 안전

## 8. 테스트 전략

기존 패턴(`MockCommandRunner`, `MockTunnelManager` + XCTest) 준수.

**신규 파일**:

| 파일 | 내용 |
|---|---|
| `PortBridgeTests/SemanticVersionTests.swift` | 파싱, 비교, 경계 케이스 |
| `PortBridgeTests/ReleaseInfoDecodingTests.swift` | JSON fixture → `ReleaseInfo` |
| `PortBridgeTests/MockReleaseFetcher.swift` | async throws 결과 주입 |
| `PortBridgeTests/UpdateCheckerTests.swift` | 핵심 비즈니스 로직 |
| `PortBridgeTests/Fixtures/github-release-latest.json` | GitHub API 실제 응답 1건 |

**`SemanticVersionTests` 케이스**:
- `"0.2.0"`, `"v0.2.0"` 동일 파싱
- `"0.2"` → `0.2.0`
- `"v1.0.0-beta.1"`, `"abc"`, `""` → nil
- `0.2.0 > 0.1.9`, `1.0.0 > 0.99.99`, `0.10.0 > 0.9.0` (lexicographic 함정)

**`UpdateCheckerTests` 케이스** (Mock fetcher + in-memory `UserDefaults(suiteName:)`):
- 새 버전 감지 → `phase == .available(...)`
- 동일 버전 → `.upToDate`
- 더 낮은 버전 → `.upToDate`
- skipped와 일치 → `.upToDate` (UI 비표시)
- skipped와 다른 더 높은 버전 → `.available` (skip은 그 버전만)
- 네트워크 에러 → `.failed`
- 24h debounce: `checkIfDue()`가 최근 체크 시 fetcher 호출 안 함
- `automaticUpdateCheckEnabled = false` 시 `checkIfDue()`는 호출 안 함, `checkNow()`는 호출
- 첫 감지 시에만 `UpdateNotifier.notify` 호출 (두 번째 launch에서 호출 안 됨)

**테스트 안 하는 것**: 실제 GitHub API 호출, CALayer 시각 검증, NSWorkspace 실제 호출, UNUserNotificationCenter 실제 권한 다이얼로그.

**검증 방법**: CLI `xcodebuild test`는 환경 이슈로 실패하므로 Xcode GUI ⌘U로 실행.

## 9. 보안 / 프라이버시

**외부로 나가는 것**:
- HTTPS GET `api.github.com/repos/yhzion/PortBridge/releases/latest`
- 헤더: `User-Agent: PortBridge/<버전>` (GitHub 요구)
- 쿠키, 인증 토큰, 사용자 데이터 일체 미전송
- 빈도: launch 1회 + 24h마다 + 수동 시

**ATS**: 기본으로 충분. `Info.plist` 변경 불필요.

**Entitlements**: 앱이 샌드박싱 안 됨 (ssh spawn). 네트워크 권한 별도 신청 불필요.

**알림 권한 요청 시점**: "처음 새 버전 감지하는 순간"에만. 앱 첫 실행 시 무조건 묻지 않음 → 거부율↓ + macOS HIG 부합.

**프라이버시 정책**: `docs/PRIVACY.md` 추가 (한 단락):
> PortBridge는 새 버전 확인을 위해 `api.github.com`에 익명 HTTPS GET 요청을 보냅니다. 사용자 데이터, IP 외 식별자, 사용 통계는 전송되지 않습니다. 환경설정에서 끌 수 있습니다.

## 10. 마이그레이션 순서

각 단계는 독립 PR로 분리 가능. Step 1~2는 사용자 영향 0.

### Step 1 — 순수 코어 (UI 없음, 영향도 0)
- `SemanticVersion.swift` + 테스트
- `ReleaseInfo.swift` + Fixture 테스트
- `ReleaseFetcher.swift` (protocol + `GitHubReleaseFetcher`)
- Bundle 확장 (`currentVersion`)
- **검증**: 단위 테스트 통과. 앱 동작 변화 없음.

### Step 2 — UpdateChecker + AppViewModel/AppPreferences 통합
- `UpdateChecker.swift` (UpdateNotifier 제외) + 테스트
- `AppPreferences.automaticUpdateCheckEnabled` 추가 + 테스트
- `AppViewModel`에 `let updates: UpdateChecker` 주입
- `AppDelegate.applicationDidFinishLaunching`에서 `updates.checkIfDue()` 호출
- **검증**: 앱 실행 후 새 버전이 있어도 UI 그대로 (메뉴/배지 연결 전), log로 확인.

### Step 3 — 메뉴 UI 통합
- `MenuBarController.buildMenu()`에 항목 4개 추가
- CALayer 배지 (`updateBadge(visible:)`)
- Observation 재-arm 패턴
- **검증**: `MARKETING_VERSION=0.0.1` 로컬 빌드로 메뉴/배지 표시 확인.

### Step 4 — 배너 알림 + CI + pbxproj 정렬
- `UpdateNotifier.swift` (`UNUserNotificationCenter`)
- 첫 감지 1회 표시 + `lastNotifiedVersion` 영속화
- `.github/workflows/release.yml` 수정: `MARKETING_VERSION=$VERSION` 주입
- pbxproj `MARKETING_VERSION = 1.0` → `0.1.0` 정렬
- `docs/PRIVACY.md` 추가
- **검증**: `v0.2.0` 태그 푸시 → CI 빌드 → 다른 기기에서 v0.1.0 실행 시 배너 + 도트 + 메뉴 항목 모두 표시.

## 11. 확장 여지 (향후 단계, 비목표)

- **Phase 2 (Sparkle 마이그레이션)**: `ReleaseFetcher` 인터페이스를 유지하고 `UpdateChecker` 내부를 Sparkle로 교체. UI 표면(배지/메뉴) 그대로 사용. 추가로 EdDSA 키쌍, appcast.xml 생성 워크플로우, notarization 필요.
- **베타 채널**: `AppPreferences.includePreReleases` 추가, fetcher가 `/releases` 사용 + SemVer pre-release 비교 로직 추가.
- **release notes 인앱 표시**: `body` 필드를 SwiftUI 시트로 렌더 (Markdown).

## 12. 합의된 결정 요약 (Q&A)

| # | 질문 | 답 |
|---|---|---|
| Q1 | 시스템 알림 배너 1회 표시? | 포함 |
| Q2 | Pre-release 처리? | 무시 (`/releases/latest`만) |
| Q3 | 자동 체크 토글 메뉴 항목? | 포함 (기본 ON) |
| Q4 | 네트워크 실패 시 UX? | 자동=조용히, 수동=결과 표시 |
| 아키텍처 | 접근 A/B/C? | B (별도 `UpdateChecker`) |
