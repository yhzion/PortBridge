# Menu Bar Extras — 디자인 문서

- **작성일**: 2026-05-21
- **상태**: Draft → 구현 대기
- **범위**: MenuBarExtra Scene 추가, 즐겨찾기(Favorites) 모델 도입, Dock 표시 정책 토글, 로그인 시 자동 시작

## 1. 문제 정의

PortBridge는 본질적으로 "한 번 켜두고 잊는" 백그라운드 유틸리티 성격을 가진다. 그러나 현재 UI는 다음을 강제한다:

1. **모든 토글이 메인 창에서만 가능** — 코드 에디터/터미널에서 작업 중 포트 하나 토글하려면 메인 창이 포커스를 빼앗는다.
2. **"지금 무엇이 켜져 있는가"의 영구 가시성이 없음** — 메인 창을 열기 전엔 알 수 없음.
3. **앱 시작 직후 사용자가 매번 같은 포트를 손으로 토글** — 자주 쓰는 터널이 정해져 있어도 자동화 수단이 없다.
4. **Dock 아이콘이 백그라운드 유틸 성격에 비해 무겁다** — 일부 사용자에겐 Dock 점유가 부담스러움.

목표: **메뉴바를 1차 인터랙션 표면으로 추가**하여 위 네 문제를 해결한다. 이 과정에서 사용자가 의도한 자동 시작 모델("즐겨찾기")을 명시적 데이터로 도입한다.

## 2. 비목표 (Non-goals)

- **세션 복원** (마지막 종료 시 활성이었던 포워딩 자동 복구) — 의도성이 약하고 우발성 위험이 큼. 즐겨찾기로 대체.
- **별도 Preferences 모달/창** — 현재 시점 설정 수가 2개 수준이라 YAGNI. 메뉴바 인라인 토글로 처리.
- **글로벌 단축키** — v2 이후 검토.
- **즐겨찾기 항목별 개별 단축키** — 동일.
- **메인 창 레이아웃 재구성** (Favorites 섹션 상단 분리 등) — v1에서는 행 단위 별 아이콘 추가에 한정. 즐겨찾기 수가 늘어나면 후속 작업.

## 3. 핵심 결정

### 3.1 자동 시작 모델: "즐겨찾기" 기반

**원칙**: 자동으로 켜지는 포워딩은 **사용자가 명시적으로 ★ 표시한 것에 한정**한다.

대안이었던 "마지막 세션 복원"은 채택하지 않는다. 이유:

| 비교 축 | 세션 복원 | 즐겨찾기 자동 시작 (채택) |
|---|---|---|
| 의도성 | 암묵적 | 명시적 |
| 우발성 | 어제 테스트로 켰던 터널이 매일 자동 실행 | 의도된 것만 |
| 모델 복잡도 | "마지막 세션 스냅샷" 영속화 | `Set<(serverId, port)>`만 |
| 메뉴바 UX와의 시너지 | 별개 | 메뉴바 드롭다운 1순위 콘텐츠 |

### 3.2 시각화: 별 (SF Symbol `star`/`star.fill`)

`star`/`star.fill` 채택. 근거:

- macOS/iOS 전반에서 ★는 "즐겨찾기"의 사실상 표준 시그널.
- 외곽선(off)과 채워짐(on)의 시각 대비가 핀/북마크보다 또렷 — 16pt 아이콘에서 결정적.
- 한국어 "즐겨찾기" 단어와 자연스럽게 매칭.

핀/북마크 후보는 검토했으나 학습 비용 또는 시각 신호 약함으로 탈락.

### 3.3 Dock 표시 정책: 토글 가능, 기본값=Dock 표시

`Info.plist`의 `LSUIElement`는 **추가하지 않는다** (앱은 `.regular` 정책으로 시작).
사용자가 메뉴바 드롭다운에서 "Show in Dock" 체크 메뉴를 끄면 `NSApp.setActivationPolicy(.accessory)`로 런타임 전환 — 재시작 없이 즉시 반영.

기본값=Dock 표시인 이유:
- 기존 v1.x 사용자에게 변경 없음 (마이그레이션 부담 0).
- "메뉴바 전용" 모드는 의도적으로 선택한 사용자만 진입.

### 3.4 환경설정 UI: 메뉴바 인라인 토글만

별도 Preferences 모달/창은 만들지 않는다. v1 설정 후보 = 2개("Launch at Login", "Show in Dock"). 전용 화면 비용이 정당화되지 않음. 설정 수가 ≥3개로 늘면 SwiftUI `Settings { }` Scene 도입 검토.

## 4. 데이터 모델

### 4.1 `FavoriteKey` (신규)

```swift
struct FavoriteKey: Hashable, Codable {
    let serverId: UUID
    let remotePort: Int
}
```

— `Forwarding` 모델은 건드리지 않는다. 즐겨찾기는 **상태(`Forwarding`)와 직교**한다: 사용자는 별을 켜놓고 토글을 끌 수도, 별 없이 임시 토글할 수도 있다.

### 4.2 `FavoriteStore` (신규)

```swift
@MainActor
final class FavoriteStore {
    private(set) var favorites: Set<FavoriteKey>

    init(defaults: UserDefaults = .standard)
    func add(_ key: FavoriteKey)
    func remove(_ key: FavoriteKey)
    func contains(_ key: FavoriteKey) -> Bool
    func toggle(_ key: FavoriteKey)
}
```

- 영속화: UserDefaults에 JSON 직렬화 (기존 `ServerStore`와 동일 패턴).
- 키: `"PortBridge.Favorites.v1"`.

### 4.3 `AppPreferences` (신규)

```swift
@MainActor
@Observable
final class AppPreferences {
    var launchAtLogin: Bool   // SMAppService.mainApp.status와 동기화
    var showInDock: Bool      // 토글 시 NSApp.setActivationPolicy 호출
}
```

- `launchAtLogin`: setter에서 `SMAppService.mainApp.register()` / `.unregister()` 호출. getter는 **항상 `SMAppService.mainApp.status`를 읽어** 사용자가 System Settings에서 직접 해제한 경우와 동기화.
- `showInDock`: setter에서 `NSApp.setActivationPolicy(.regular | .accessory)` 즉시 호출.

## 5. `AppViewModel` 확장

```swift
@MainActor
@Observable
final class AppViewModel {
    // 기존 ...

    let favorites: FavoriteStore      // 신규
    let preferences: AppPreferences   // 신규

    // 즐겨찾기 조회
    func isFavorite(serverId: UUID, port: Int) -> Bool
    func toggleFavorite(serverId: UUID, port: Int)

    // 메뉴바 콘텐츠
    /// 즐겨찾기 목록을 뷰 표시용으로 정규화 — 서버 이름, 활성 상태, 프로세스명까지 묶어 반환.
    var favoriteRows: [FavoriteRow]
    /// 즐겨찾기에 속하지 않는 활성 포워딩만 — 메뉴바 "Active" 섹션용.
    var nonFavoriteActive: [Forwarding]

    // 앱 시작 시 즐겨찾기 자동 시작
    func startFavoritesIfEnabled() async
}

struct FavoriteRow: Identifiable, Equatable {
    let id: FavoriteKey
    let serverDisplayName: String
    let remotePort: Int
    let localPort: Int?         // 활성일 때만
    let processName: String?    // 마지막 스캔에서 알려진 경우
    let state: ForwardingState  // .idle 포함 (즐겨찾기지만 꺼져있을 때)
}
```

- `favoriteRows`는 `forwardings` + `serverSections` 양쪽에서 lazy 조회 — 별도 캐시 없음. SwiftUI는 `@Observable`로 자동 재계산.
- `nonFavoriteActive`는 `activeForwardings` 중 `FavoriteKey`에 속하지 않는 것.

## 6. UI 변경

### 6.1 메인 창 — `ForwardingRowView`

- 행의 **leading 위치**에 별 버튼 추가 (16pt, accentColor).
- `star` (off) / `star.fill` (on) 토글, `.borderless` 스타일.
- 클릭 시 `viewModel.toggleFavorite(...)` 호출.
- 기존 on/off 토글 스위치는 trailing에 그대로 유지. 별 버튼과 시각·동선 분리로 의미 구분.

```
┌──────────────────────────────────────────────────┐
│ [★]  5432   postgres                  [● On]    │
│ [☆]  6379   redis                     [○ Off]   │
└──────────────────────────────────────────────────┘
```

### 6.2 메인 창 — 즐겨찾기 가능 시점

- **현재 메인 창의 포트 행에서 표시되는 모든 포트가 즐겨찾기 대상.** 서버가 `~/.ssh/config` 자동 인식이든 수동 추가든 무관 — 스캔 결과로 노출된 포트 행에는 모두 별 버튼이 붙는다.
- v1에서는 임의 포트 번호를 직접 입력하는 UI를 도입하지 않는다 (별도 기능). 따라서 즐겨찾기는 항상 "이미 한 번 이상 스캔에서 발견된 포트"에 한정된다.
- 단, **저장된 `FavoriteKey`는 스캔 결과와 독립적으로 영속화**된다. 서버가 일시적으로 오프라인이거나 원격 프로세스가 내려가 스캔에 안 보여도 즐겨찾기 항목은 유지되며, 메뉴바에는 비활성(off) 상태로 표시된다.

### 6.3 메뉴바 — `MenuBarContent` (신규)

```
┌─ PortBridge ──────────────────────────────────────┐
│  ★ Favorites                                      │
│    ● db-prod:5432   postgres                      │
│    ● web-stage:8080 node                          │
│    ○ jump:6379      redis                         │
│  ─────────────────────────────────────────────── │
│  ● Active                                ← 활성   │ 있을 때만
│    ● exp:9000                                     │
│  ─────────────────────────────────────────────── │
│  ⚠︎ 1 error — db-prod down                >       │ 에러 있을 때만
│  ─────────────────────────────────────────────── │
│  Open Main Window                            ⌘O  │
│  ☐ Launch at Login                                │
│  ☑ Show in Dock                                   │
│  ─────────────────────────────────────────────── │
│  Quit PortBridge                             ⌘Q  │
└───────────────────────────────────────────────────┘
```

- **항목 시각화**: 좌측 status dot (활성=녹색, 비활성=회색), 모노스페이스 `host:port` + 회색 프로세스명. NSMenu 관습상 토글 스위치는 사용하지 않음.
- **호스트 이름**: `serverDisplayName(for:)`이 nil인 경우 (서버 삭제됨) 항목 자체를 표시하지 않고 다음 스캔 시 cleanup 대상으로 큐잉.
- **항목 클릭**: 토글 (켜진 것은 끄고, 꺼진 것은 켬). 메뉴는 닫힘.
- **⌥ 클릭**: 메인 창 활성화 + 해당 서버 섹션 expand. (편의 단축)
- **에러 요약 클릭**: 메인 창 활성화 + 에러 토스트 렌더 영역 스크롤.
- **에러 0개일 때**: 그 줄은 렌더링하지 않는다 (양성 메시지 표시 안 함).
- **Favorites 0개일 때 empty state**:

```
  ★ Favorites
    메인 창에서 ★를 눌러 즐겨찾기를 추가하세요
    [ Open Main Window ]
```

### 6.4 메뉴바 아이콘

- SF Symbol: 아래 매핑 — 활성 즐겨찾기 수에 따라 변형.
  - 활성 0개: `arrow.triangle.swap` (회색, secondary)
  - 활성 ≥1개: `arrow.triangle.swap` (accentColor)
  - 에러 있음: `arrow.triangle.swap` + `exclamationmark` 오버레이 변형 (red)
- 메뉴바 라벨 텍스트는 표시하지 않음 (아이콘만).

## 7. 앱 시작 시 동작

### 7.1 시작 순서

```
applicationWillFinishLaunching
  → AppDelegate.init
    → AppSingleInstance check
    → TunnelManager.cleanupOrphanedTunnels()
    → viewModel = AppViewModel()
      → ServerStore, ScannerCommandRunner, TunnelManager, FavoriteStore, AppPreferences 초기화
  → NSApp.setActivationPolicy(prefs.showInDock ? .regular : .accessory)
    ← 영속화된 사용자 선택을 반영해 깜빡임 없이 즉시 적용

applicationDidFinishLaunching
  → if prefs.launchAtLogin {
        Task { try? await Task.sleep(for: .seconds(5)); await viewModel.startFavoritesIfEnabled() }
    }
```

### 7.2 `startFavoritesIfEnabled()`

- 즐겨찾기 항목들을 **병렬**로 시작 (사용자 토글과 동일 경로 `toggleForwarding` 활용).
- 시작 전 5초 그레이스 대기 — VPN/네트워크 안정화.
- 실패 항목은 기존 `.error(stderr)` 상태로 떨어지고, 에러 토스트는 maxErrorsShown=3 제한으로 자동 합산.

### 7.3 자동 시작 감지

- macOS는 SMAppService로 로그인 시 실행된 경우와 사용자가 수동 실행한 경우를 구분할 수 있는 직접 API가 없다.
- 차선책: **`launchAtLogin` 토글이 켜져 있으면 매 실행 시 즐겨찾기 자동 시작**으로 단순화. 사용자가 명시적으로 토글을 켰다는 사실이 의도의 증거.

## 8. Dock 정책 전환

### 8.1 런타임 전환

```swift
preferences.showInDock = newValue
NSApp.setActivationPolicy(newValue ? .regular : .accessory)
```

- 메인 창이 열려 있는 상태에서 `.accessory`로 전환 시 메인 창은 그대로 유지된다 (NSApp 정책 변경은 윈도우를 닫지 않는다). 사용자가 직접 닫을 때까지 표시.
- `.accessory` → `.regular` 전환 시 Dock 아이콘이 즉시 다시 나타남.

### 8.2 accessory 모드의 종료

- Dock 우클릭이 사라지므로, 종료 경로는:
  1. 메뉴바 드롭다운의 "Quit PortBridge" ⌘Q
  2. 시스템의 ⌘Q 단축키 (앱이 frontmost일 때)
  3. Activity Monitor / `killall`

— v1 범위에선 (1), (2)면 충분.

### 8.3 메인 창 자동 노출 규칙

- **`.regular` 모드 시작**: 기존 동작 유지 (WindowGroup가 메인 창 자동 표시).
- **`.accessory` 모드 시작**: 메인 창 자동 노출하지 않음. WindowGroup은 선언하지만 최초 표시는 사용자 액션("Open Main Window") 시점.

→ 구현 방식: `WindowGroup`을 그대로 두되, `.accessory` 모드일 때는 launching 직후 메인 윈도우를 close하거나, SwiftUI 4의 `Scene` 조건부 노출 패턴 사용. 상세 구현 방식은 구현 계획에서 결정.

## 9. 파일 변경 요약

| 파일 | 변경 종류 | 비고 |
|---|---|---|
| `PortBridge/PortBridgeApp.swift` | 수정 | MenuBarExtra Scene 추가, activation policy 초기화 |
| `PortBridge/AppDelegate` (PortBridgeApp.swift 내) | 수정 | preferences, favorites 초기화. launchAtLogin 자동 시작 |
| `PortBridge/ViewModels/AppViewModel.swift` | 수정 | favorites/preferences 보유, FavoriteRow 노출, startFavoritesIfEnabled |
| `PortBridge/Storage/FavoriteStore.swift` | **신규** | UserDefaults JSON 영속화 |
| `PortBridge/Storage/AppPreferences.swift` | **신규** | launchAtLogin, showInDock 영속화 + side effect |
| `PortBridge/Models/FavoriteKey.swift` | **신규** | (serverId, remotePort) |
| `PortBridge/Views/ForwardingRowView.swift` | 수정 | leading 별 버튼 추가 |
| `PortBridge/Views/MenuBarContent.swift` | **신규** | 드롭다운 SwiftUI 뷰 |
| `PortBridgeTests/FavoriteStoreTests.swift` | **신규** | persistence, add/remove/toggle 동작 |
| `PortBridgeTests/AppViewModel+FavoritesTests.swift` | **신규** | favoriteRows, nonFavoriteActive, startFavoritesIfEnabled |
| `Info.plist` | 변경 없음 | LSUIElement 추가하지 않음 |

## 10. 테스트 전략

### 10.1 단위 테스트

- `FavoriteStore`: add/remove/toggle 멱등성, UserDefaults round-trip.
- `AppViewModel.favoriteRows`: 다양한 조합 (즐겨찾기만, 활성만, 둘 다, 둘 다 아님) → 출력 순서·내용 검증.
- `AppViewModel.nonFavoriteActive`: 즐겨찾기 = 활성 일 때 빈 배열.
- `AppViewModel.startFavoritesIfEnabled`: 즐겨찾기 3개 중 1개 실패 시 나머지 2개 활성 + 에러 1개.

### 10.2 통합 / UI 테스트

- 메인 창에서 별 토글 → 메뉴바 표시 변경 확인 (SwiftUI 환경 공유).
- Dock 토글 → `NSApp.activationPolicy` 실제 변경 확인.
- (`xcodebuild test`는 LaunchServices 환경 이슈로 CLI 검증 불가. Xcode GUI ⌘U에서 검증.)

### 10.3 수동 검증 시나리오

1. 즐겨찾기 0개 상태에서 메뉴바 열기 → empty state 확인.
2. 즐겨찾기 2개 등록 → 메뉴바에 즉시 반영.
3. "Show in Dock" 끔 → Dock 아이콘 사라짐, 메인 창은 그대로.
4. "Show in Dock" 끔 + 메인 창 닫음 → 앱 살아있음 (메뉴바로 다시 열기 가능).
5. "Launch at Login" 켬 → 로그아웃 후 재로그인 → 5초 후 즐겨찾기 자동 활성.
6. System Settings → Login Items에서 직접 해제 → 앱 메뉴 토글이 자동으로 OFF로 동기화.

## 11. 향후 확장 여지 (v2+)

- 즐겨찾기 수가 일상적으로 5개 이상이 되면 메인 창 상단 별도 "Favorites" 섹션 도입 (이전 시안의 옵션 D).
- 글로벌 단축키 (⌃⌥⌘P 등) — 메뉴바 토글.
- 메뉴바 아이콘 라벨에 활성 카운트 배지.
- "메뉴바 전용 모드" 기본값 변경 (충분한 사용자 피드백 후).
