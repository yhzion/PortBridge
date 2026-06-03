# 포워딩 항목 표시 형식 통일 — 설계

- **날짜**: 2026-06-03
- **상태**: 설계 승인됨, spec 검토 대기
- **대상**: apps/macos (PortBridge)

## 1. 배경 / 문제

포워딩 중(또는 포워딩 가능)인 항목을 표시하는 형식이 세 표면에서 제각각이다.

| 위치 | 현재 형식 | 호스트 식별 |
|------|----------|------------|
| 메인 윈도우 행 (`ForwardingRowView`) | `:포트` 컬럼 + (포워딩 중일 때만) `name (host) · → :로컬 포워딩 중` 부제 + (비활성) `scopeLabel` + 프로세스 부제 | 조건부 (포워딩 중일 때만 부제에) |
| 메뉴바 Favorites (`MenuBarController.favoriteTitle`) | `● name (host):포트 프로세스` | ✅ |
| 메뉴바 Active 비즐겨찾기 (`MenuBarController` buildMenu) | `:포트` | ❌ 없음 |

핵심 결함: 메뉴바 **Active(비즐겨찾기)** 섹션은 `:포트번호`만 표시해 어느 서버 소속인지 식별 불가. `Forwarding`에 `serverId`는 있으나(`serverDisplayName(for:)`로 호스트 조회 가능) 렌더링에서 누락됨. 서로 다른 서버가 같은 포트를 비즐겨찾기로 포워딩하면 동일한 `:8080`이 중복 표시되어 구분 불가 — 메인 윈도우 #150 버그와 동형의 표시상 모호함(단, 토글 라우팅은 `fw.serverId` 사용으로 올바름).

## 2. 목표

**단일 캐노니컬 표시 모델을 도입**해 세 표면이 모두 같은 소스에서 필드·순서·라벨을 가져오게 한다. 색상·레이아웃은 각 표면의 매체에 맞춰 자율적으로 렌더한다(메뉴바=평문 문자열, 메인 윈도우=리치 SwiftUI).

### 비목표 (건드리지 않음)
- dimming 판정(`isDimmed`/`shouldDim`)
- 연결 상태 판정(`isConnected`/`isActiveState`)
- 토글 라우팅(`toggleForwarding`, `stopActiveForwarding`)
- 메뉴 스캔 스로틀, 아이콘/배지 로직

## 3. 캐노니컬 포맷 (확정)

```
[상태표시] host:remotePort[ → :localPort][ · processName]
```

- **host** = `Server.displayName` = `name (host)` 또는 `host`
- **상태 4종 규칙**:

| 상태 | `→ :localPort` | 메뉴 dot | 메인 윈도우 인디케이터 |
|------|---------------|---------|----------------------|
| active | 표시 | `●` | 초록 원 (`circle.fill`, green) |
| starting | 숨김 | `●` | 스피너 (`ProgressView`) |
| error | 숨김 | `○` | 빨강 삼각형 (`exclamationmark.triangle.fill`) + info 툴팁(유지) |
| inactive | 숨김 | `○` | 빈 원 (`circle`, secondary) |

- `→ :localPort`는 **active 상태에서만** 표시.
- 텍스트 라인(`line`)은 상태표시 dot/심볼을 **포함하지 않는다** — 상태는 선행 인디케이터로 별도 렌더.

> **starting의 localPort 처리 (확인됨)**: `AppViewModel.startForwarding`은 placeholder를 `.starting`으로 만들 때 `localPort`를 **이미 채운다**(연결 확정 전 *후보값*). 즉 starting에서 localPort 값은 존재하지만, 연결이 확정되지 않았으므로 `→ :localPort`를 **의도적으로 숨긴다**. 화살표는 "확정된 활성 포워딩"의 신호로만 쓴다.

### 3.1 host 표현 계약 (테스트 고정용)
`host` = `Server.displayName`:
```
name == nil  → host                  (예: "1.2.3.4")
name != nil  → "name (host)"         (예: "myserver (1.2.3.4)")
```
- `name`은 입력 시 trim 후 빈 문자열이면 `nil`로 정규화된다(`AddServerSheet.swift:112`). 따라서 `name`이 `""`인 경우는 발생하지 않으며 `ForwardingDisplay` 테스트도 그 가정을 따른다.
- `name == host`(사용자가 호스트를 이름으로 입력) 시 `"host (host)"`가 되나, 이는 기존 `Server.displayName`의 행동이며 본 작업의 범위 밖(변경하지 않음).

### 3.2 줄바꿈/생략 정책
- **메인 윈도우 행**: 한 줄 유지(`.lineLimit(1)`). 단 현행 `.truncationMode(.tail)`은 host-first에서 꼬리(포트·프로세스 — 식별에 가장 유용)를 먼저 자른다. 따라서 **host에 middle truncation**을 적용해 `:remotePort → :localPort · process`가 보존되도록 한다(SwiftUI에선 host `Text`만 `.truncationMode(.middle)`, 나머지 세그먼트는 자르지 않음).
- **메뉴바**: `NSMenuItem`은 AppKit이 자동 폭 처리(자체 truncation). 별도 정책 불필요.

### 예시
```
active:   ● myserver (1.2.3.4):8080 → :3000 · nginx
inactive: ○ myserver (1.2.3.4):5432 · postgres
```

## 4. 승인된 표면별 적용 (정보에 입각한 결정)

사용자는 권장안(메인 윈도우 행 호스트 생략, scopeLabel 유지)을 두 번 거부하고 **완전 균질**을 택했다. 현실적 밀도 목업과 scopeLabel 손실 경고를 본 뒤 재승인함.

### 4.1 메인 윈도우 행 (`ForwardingRowView`)
- **호스트를 모든 행에 표시** — 섹션 헤더와 중복되지만 메뉴바와 글자 동일.
- **`scopeLabel` 완전 삭제** — "모든 인터페이스"/"로컬 전용"/바인드 주소 정보 영구 손실(의도된 결정). 메뉴바엔 원래 없으므로 통일을 위해 제거.
- 우측 정렬 monospace 볼드 포트 컬럼 + 상태별 색상은 **한 줄 평문 텍스트(`line`)로 통합**. 상태는 선행 인디케이터(SF Symbol+색)로만 전달.
- **유지**: 즐겨찾기 ★ 버튼, "브라우저에서 열기" 버튼(active일 때), error info 아이콘 툴팁 — 인터랙티브/메인 전용 요소.

현실 밀도(긴 호스트명 × 다중 포트) — 승인됨:
```
┌─ prod-api-gateway-seoul (10.42.118.203)
│  ★  ● prod-api-gateway-seoul (10.42.118.203):8080 → :3000 · nginx      [브라우저에서 열기]
│  ★  ○ prod-api-gateway-seoul (10.42.118.203):5432 · postgres
│  ★  ● prod-api-gateway-seoul (10.42.118.203):6379 → :6379 · redis      [브라우저에서 열기]
│     ○ prod-api-gateway-seoul (10.42.118.203):9090 · prometheus
```

### 4.2 메뉴바 Favorites
- `favoriteTitle`을 캐노니컬 `line`에서 생성: `"\(statusDot) \(line)"`.
- 기존과 거의 동일하나 active 시 `→ :localPort` 추가됨.

### 4.3 메뉴바 Active (비즐겨찾기)
- **진짜 패리티**: 호스트 + 프로세스명 추가. 현재 `[Forwarding]`이라 둘 다 없으므로 enrich 필요.
- `favoriteRows`와 동일 방식으로 `serverSections`에서 processName, `serverDisplayName(for:)`에서 호스트 조회.

## 5. 아키텍처 — 데이터 모델이 핵심 작업

포맷 문자열이 아니라 **공유 값 타입**이 통일의 본질이다.

### 5.1 신규 값 타입 `ForwardingDisplay` (Models/ForwardingDisplay.swift)
```swift
nonisolated struct ForwardingDisplay: Equatable {
    enum Status: Equatable { case active, starting, error, inactive }

    let status: Status
    let host: String          // Server.displayName
    let remotePort: Int
    let localPort: Int?       // status == .active일 때만 비-nil (init이 정규화)
    let processName: String?

    /// 불변식 강제: init이 active 외 상태의 localPort를 nil로 정규화.
    /// (Finding 2) 커스텀 init이 없으면 @testable 테스트에서 internal memberwise
    /// init으로 status: .inactive, localPort: 3000 같은 위반 조합을 만들 수 있으므로
    /// 반드시 명시 init으로 정규화한다.
    init(status: Status, host: String, remotePort: Int, localPort: Int?, processName: String?) {
        self.status = status
        self.host = host
        self.remotePort = remotePort
        self.localPort = (status == .active) ? localPort : nil   // 정규화
        self.processName = processName
    }

    /// 순서·라벨의 단일 출처. 상태 dot/심볼은 미포함.
    /// "host:remotePort[ → :localPort][ · processName]"
    var line: String { ... }

    /// 메뉴바 평문용 선행 표시.
    var statusDot: String { (status == .active || status == .starting) ? "●" : "○" }
}
```
- `line`은 `status == .active`일 때만 `→ :localPort` 포함, processName 있으면 ` · processName` 추가.
- **불변식**: `localPort != nil ⇒ status == .active`. init이 강제하므로(active 외엔 localPort를 nil로 떨굼) 위반 조합은 표현 불가 — `@testable` 경유로도. 원본 `Forwarding.localPort`가 starting/error에서 후보값을 들고 있어도 무시된다.
- **`status`는 raw `Forwarding.State`가 아니라 "신뢰 보정된 *표시* 상태"다.** 각 생성처가 결정한다(§5.2/§5.3). 특히 Favorites는 offline 방어를 status에 접어 넣어야 한다(아래 Finding 1).
- **Sendable**: 기존 모델(`Server`/`RemotePort`/`Forwarding`)과 동일하게 `Sendable`을 **명시 선언하지 않는다**(전 필드 값 타입이라 모듈 내 암묵 적용; 현행 패턴 일치). 크로스-액터 전달이 필요해지면 컴파일러가 알려줄 때 추가.

### 5.2 빌드 위치 — `AppViewModel` (확정, "또는" 제거)
- `Forwarding.State` → `ForwardingDisplay.Status` 매핑은 **raw 매핑**(`.active→.active`, `.starting→.starting`, `.error→.error`, `.idle/nil→.inactive`)과 **신뢰 보정**(offline 게이트) 두 단계로 본다.
- **메뉴 Active**: `nonFavoriteActive: [Forwarding]`는 **그대로 유지**한다 — 메뉴 아이템 `representedObject = fw`가 `stopActiveForwarding` 토글 라우팅에 필요하기 때문(`MenuBarController.swift:157,295`). 대신 `AppViewModel`에 `func display(for forwarding: Forwarding) -> ForwardingDisplay`를 추가: host는 `serverDisplayName(for: fw.serverId)`, processName은 `serverSections`의 해당 포트에서 조회(= `favoriteRows`와 동일 enrich 경로). status는 raw 매핑(Active 섹션은 현행에도 offline 억제가 없음).
- **Favorites (Finding 1 — 신뢰 보정 필수)**: `FavoriteRow`는 이미 `serverDisplayName`/`remotePort`/`localPort`/`processName`/`state`/`isOffline`을 보유하므로, 파생 계산 프로퍼티 `var display: ForwardingDisplay`를 추가한다. **단, status는 raw `state`가 아니라 offline 게이트를 적용한 값이어야 한다**:
  ```
  status = isOffline ? .inactive : rawMap(state)
  ```
  이는 현행 `favoriteTitle`의 dot 로직 `!isOffline && isActiveState(state)`(`MenuBarController.swift:241`)과 **동치**다(offline → ○, no arrow). `AppViewModelFavoritesTests.swift:139/152`("offline 서버의 stale `.active`는 ●로 보이면 안 됨")를 보존한다. `isConnected`/`isDimmed` **로직 자체는 변경하지 않는다**(비목표) — 그 *결과*를 status에 주입할 뿐.

### 5.3 소비처 (메뉴 2 + 메인 윈도우 행 2 호출부)
1. `MenuBarController.favoriteTitle(for: row)` → `"\(row.display.statusDot) \(row.display.line)"`. dot이 offline 보정된 status에서 나오므로(§5.2) 기존 방어 유지.
2. `MenuBarController` buildMenu Active 아이템 title → `"\(d.statusDot) \(d.line)"` (`d = viewModel.display(for: fw)`). `representedObject`는 종전대로 `fw`.
3. `ForwardingRowView` (메인 윈도우) — 상태 인디케이터(심볼) + `Text(d.line)`(host 세그먼트만 middle truncation) + ★/브라우저 버튼.
   - **두 호출부 모두 host 주입 필요 (Finding 3)**:
     - **활성 행** `ServerListView.swift:191` — 이미 `serverDisplayName: vm.serverDisplayName(for:)` 주입함(변경 없음).
     - **비활성 행** `ServerSectionView.swift:96-99` — 현재 `serverDisplayName: nil`. §4.1의 "모든 행 host 표시"를 위해 `section.server.displayName`을 주입하도록 변경한다.
   - 권장 리팩토링: 두 호출부의 인자 표류를 막기 위해 `ForwardingRowView`가 개별 인자 대신 `ForwardingDisplay`(+ port/콜백)를 받게 한다. 그러면 host 누락이 타입으로 차단됨.
   - **접근성**: `accessibilityLabel`은 `line`을 **그대로 쓰지 않는다**. `line`은 `→`(U+2192)·`·`(U+00B7)를 포함해 VoiceOver 발음이 어색하므로(현행은 "포워딩 중" 같은 단어형으로 별도 구성), `ForwardingDisplay`에 음성용 `accessibilityText`(예: `"myserver (1.2.3.4) 포트 8080, 로컬 3000으로 포워딩 중, nginx"`)를 별도 제공하고 행은 이를 사용한다. 시각 라인과 음성 라인의 필드·순서는 동일하게 유지.

## 6. 테스트 전략

- **`ForwardingDisplayTests`** (신규): 불변식 `localPort != nil ⇒ active` 때문에 단순 4×2×2=16이 아니라 **유효 조합만** 검증한다(축: 상태 4종 × process 유/무 = 8):
  - active × {process 유/무} → `→ :localPort` 항상 포함, dot `●` (2케이스)
  - starting × {process 유/무} → 화살표 없음, dot `●` (2케이스)
  - error × {process 유/무} → 화살표 없음, dot `○` (2케이스)
  - inactive × {process 유/무} → 화살표 없음, dot `○` (2케이스)
  - host 계약(§3.1): `name==nil` → `host`, `name!=nil` → `"name (host)"` 두 분기
  - `accessibilityText`가 `→`/`·` 미포함 단어형인지 검증
  - **init 정규화(Finding 2)**: `init(status: .inactive, localPort: 3000, …)`의 결과 `localPort == nil`임을 검증(위반 조합이 표현 불가함을 고정).
- **`AppViewModelFavoritesTests`**: offline 서버의 stale `.active` 즐겨찾기에서 `display.status == .inactive`(→ dot `○`, 화살표 없음)임을 검증 — 기존 `:139/:152` 방어를 캐노니컬 경로로 회귀 고정(Finding 1).
- **`MenuBarControllerLogicTests`**: Active 섹션 타이틀이 호스트·프로세스를 포함하는지 검증(현재 사각).
- 기존 `ForwardingTests`, `AppViewModelFavoritesTests`, `MenuBarControllerLogicTests` 회귀 확인.
- Swift 테스트 로컬 실행 불가(macOS 26 LaunchServices) — CI parity 잡(#60)으로 검증.

## 7. 리스크 / 트레이드오프

1. **밀도/가독성 회귀**(메인 윈도우): 호스트 반복 + 포트 컬럼 색상·monospace 상실. 승인됨. host middle-truncation(§3.2)으로 식별 정보 보존.
2. **정보 손실**: `scopeLabel`(바인드 스코프) 영구 제거. 승인됨.
3. **화살표 점멸(UX 노트)**: `localPort`는 `Forwarding`에서 non-optional이라 error 후에도 잔존하지만, factory가 active 외엔 `nil`로 떨어뜨리므로 active→error 전이 시 `→ :3000`이 사라진다. 의도된 동작(화살표 = 확정 활성 신호). 같은 행에서 나타났다 사라지는 현상은 정상.
4. **접근성 회귀 방지**: 시각 `line`을 a11y에 직접 쓰지 않고 별도 `accessibilityText` 제공(§5.3). VoiceOver가 `→`/`·`를 어색하게 읽는 회귀를 차단.
5. **CI 의존**: 로컬 Swift 테스트 불가로 CI parity 잡(#60)에 의존. 로컬은 `xcodebuild build-for-testing`까지만 가능(컴파일 게이트), 실제 `test` 실행은 CI에서(메모리 `swift-test-execution-blocked-macos26`).
6. **swiftformat docComments**: 새 파일/주석은 선언 앞 `///` 사용(로컬 lint가 CI보다 느슨할 수 있음 — 메모리 `ffi-swift-lint-gate` 참조).
