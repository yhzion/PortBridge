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

- `→ :localPort`는 **active 상태에서만** 표시(localPort가 확정된 경우).
- 텍스트 라인(`line`)은 상태표시 dot/심볼을 **포함하지 않는다** — 상태는 선행 인디케이터로 별도 렌더.

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
    let localPort: Int?       // active일 때만 채움
    let processName: String?

    /// 순서·라벨의 단일 출처. 상태 dot/심볼은 미포함.
    /// "host:remotePort[ → :localPort][ · processName]"
    var line: String { ... }

    /// 메뉴바 평문용 선행 표시.
    var statusDot: String { (status == .active || status == .starting) ? "●" : "○" }
}
```
- `line`은 active일 때만 `→ :localPort` 포함, processName 있으면 ` · processName` 추가.
- `localPort`는 `status == .active`일 때만 비-nil이 되도록 팩토리에서 보장.

### 5.2 빌드 위치 — `AppViewModel`
- `Forwarding.State` → `ForwardingDisplay.Status` 매핑 헬퍼.
- 메뉴 Active용: `nonFavoriteActive`를 `ForwardingDisplay` 산출로 정비(또는 신규 `activeMenuDisplays`). processName은 `serverSections`에서, host는 `serverDisplayName(for:)`에서.
- Favorites용: `favoriteRows` 산출 시 `ForwardingDisplay`도 함께 제공(또는 `FavoriteRow`에서 파생). 기존 `FavoriteRow`의 dimming/연결 필드는 유지 — 표시 포맷만 캐노니컬로.

### 5.3 소비처 3곳
1. `MenuBarController.favoriteTitle(for:)` → `"\(d.statusDot) \(d.line)"`.
2. `MenuBarController` buildMenu Active 아이템 title → `"\(d.statusDot) \(d.line)"`.
3. `ForwardingRowView` → 상태 인디케이터(심볼) + `Text(d.line)` + ★/브라우저 버튼. `accessibilityLabel`도 같은 `d.line`에서 파생.

## 6. 테스트 전략

- **`ForwardingDisplayTests`** (신규): `line` 생성을 상태 4종 × (프로세스 유/무) × (localPort 유/무) 조합으로 검증. statusDot 매핑 검증. 이 순수 값 타입이 통일의 단일 진실이므로 단위 테스트 사각이 없어야 함.
- **`MenuBarControllerLogicTests`**: Active 섹션 타이틀이 호스트·프로세스를 포함하는지 검증(현재 사각).
- 기존 `ForwardingTests`, `AppViewModelFavoritesTests`, `MenuBarControllerLogicTests` 회귀 확인.
- Swift 테스트 로컬 실행 불가(macOS 26 LaunchServices) — CI parity 잡(#60)으로 검증.

## 7. 리스크 / 트레이드오프

1. **밀도/가독성 회귀**(메인 윈도우): 호스트 반복 + 포트 컬럼 색상·monospace 상실. 승인됨.
2. **정보 손실**: `scopeLabel`(바인드 스코프) 영구 제거. 승인됨.
3. **CI 의존**: 로컬 Swift 테스트 불가로 CI parity 잡에 의존.
4. **swiftformat docComments**: 새 파일/주석은 선언 앞 `///` 사용(로컬 lint가 CI보다 느슨할 수 있음 — 메모리 `ffi-swift-lint-gate` 참조).
