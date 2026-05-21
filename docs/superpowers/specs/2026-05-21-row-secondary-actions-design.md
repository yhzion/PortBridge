# 행 내부 부 동작의 접근성 통합 설계

날짜: 2026-05-21
대상: `ForwardingRowView`, `ServerSectionView`
관련 리뷰 항목: UI/UX 리뷰 #3 (OpenInBrowserButton 키보드 접근), #5 (chevron 탭 영역)

## 1. 배경

PortBridge UI/UX 리뷰에서 두 가지 접근성 결함이 보고됐다.

- **#3 — OpenInBrowserButton**: `ForwardingRowView.swift:87-89`에서 `isRowHovering`이 true일 때만 "브라우저에서 열기" 버튼이 노출된다. 마우스 호버 외 경로(키보드 Tab, VoiceOver)로는 도달할 수 없다.
- **#5 — Chevron 탭 영역**: `ServerSectionView.swift:108-121`의 chevron은 12pt 너비 `Button`이며, 동시에 행 전체에 `onTapGesture { handleRowTap() }`가 걸려 있다. 같은 동작(펼침/접힘)이 두 노드로 노출되고, VoiceOver는 작은 chevron만 별도 버튼으로 인식해 탭 영역이 좁다.

두 결함은 표면적으로 다르지만 본질적으로 같은 구조 문제다 — "행 내부 작은 인터랙티브 요소"의 노출 정책이 마우스 호버에 편향됐고, 키보드·VoiceOver 경로가 누락됐다.

## 2. 설계 원칙

> **행은 의미 단위로 묶고, 모든 동작 경로(마우스·키보드·VoiceOver)가 도달 가능해야 한다.**

세부 원칙:

1. **부 동작이 의미 있는 상태에서는 항상 노출한다.** 호버 의존 노출은 키보드·VO 사용자 배제이므로 금지.
2. **행 자체가 Tab stop이며 Enter로 주 동작.** 행 안의 부 버튼은 별도 Tab stop으로 도달.
3. **같은 동작을 두 번 노출하지 않는다.** 시각 단서(chevron 아이콘 등)는 접근성 트리에서 숨기고, 동작은 한 노드(행)로 통합.

## 3. ForwardingRowView 변경

### 시각

- `isRowHovering` state는 행 배경 hover 피드백 용도로 유지하되, **OpenInBrowserButton 노출 게이트로는 사용하지 않는다**.
- Active 상태(`forwarding?.state == .active` && `localPort != nil`)인 행에는 OpenInBrowserButton을 **항상 노출**한다.

### 구조

행 전체 `HStack`을 `Button(action: onToggle)`으로 감싸 자연스러운 Tab focus / Enter / Space 처리를 얻는다.

```swift
Button(action: onToggle) {
    HStack(alignment: .center, spacing: 10) {
        statusIndicator
        if showPortColumn { Text(":\(port.port)") ... }
        VStack { rightPrimary, rightSecondary }
        Spacer(minLength: 4)
        if isActive, let local = forwarding?.localPort {
            OpenInBrowserButton(localPort: local)
        }
        if case .error(let msg) = forwarding?.state {
            Image(systemName: "info.circle").help(String(msg))
        }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.disabled(isStarting)
.onHover { isRowHovering = $0 }
.accessibilityElement(children: .contain)
.accessibilityLabel(accessibilityLabel)  // 기존 private computed property (현 코드 :127-133) 그대로 사용
.accessibilityHint(forwarding?.state == .active ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기")
```

### 접근성 트리 변화

| 항목 | Before | After |
|---|---|---|
| Combine 정책 | `.combine` | `.contain` |
| `isButton` 트레잇 | 명시 부여 | Button이 자동 부여 |
| OpenInBrowserButton 노출 | hover 시에만 시각, 트리에선 부모 라벨에 흡수 | Active일 때 항상 시각 + 별도 노드 |
| Tab stop | 행 자체가 stop 아님 (onTapGesture) | 행 Button = stop, 자식 버튼 = stop |

### 영향 받는 코드

- `:55` `@State private var isRowHovering` — 유지 (행 배경 hover 효과에만)
- `:57-109` body — Button 래핑으로 재구성
- `:87` `if isActive, let local = forwarding?.localPort, isRowHovering` → `if isActive, let local = forwarding?.localPort`
- `:100-103` `.onTapGesture { ... }` 제거 (Button action으로 대체)
- `:105-108` `.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)` 제거

## 4. ServerSectionView 변경

### Chevron — 시각 단서로 격하

`:108-121`의 chevron `Button`을 단순 `Image`로 교체한다. 행 전체가 disclosure 역할을 하므로 chevron은 시각 단서로만 기능한다.

```swift
if !isOffline {
    Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 12)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
} else {
    Color.clear.frame(width: 12, height: 12)
}
```

### 행 = disclosure Button

`ForwardingRowView`와 동일 패턴으로 행 전체를 Button으로 감싼다. 단, `refresh`·`ellipsis Menu`는 별도 동작이므로 자식 Tab stop으로 유지해야 한다 — 따라서 행 라벨링은 `.combine`이 아닌 **`.contain`** 사용.

```swift
private var sectionHeader: some View {
    Button(action: handleRowTap) {
        HStack(spacing: 8) {
            chevronImageOrSpacer
            ServerMonogram(server: section.server, status: statusDot, dimmed: isOffline)
                .accessibilityHidden(true)
            nameAndHost
            Spacer(minLength: 8)
            countBadgeIfAny
            refreshOrProgress
            ellipsisMenu
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(primaryLabel) \(secondaryLabel)")
    .accessibilityValue(section.isExpanded ? "펼침" : "접힘")
    .accessibilityHint(isOffline
        ? "이중 탭하여 재스캔"
        : "이중 탭하여 \(section.isExpanded ? "접기" : "펼치기")")
}
```

오프라인 분기 동작은 `handleRowTap()` 내부에 그대로 보존된다 (`:180-186`).

### 접근성 트리 변화

| 항목 | Before | After |
|---|---|---|
| chevron 노드 | 별도 Button | `.accessibilityHidden(true)` → 트리에서 제거 |
| 행 동작 노출 | `onTapGesture` (VO 미노출) | 행 Button = 명시적 disclosure 노드 |
| Tab 흐름 | chevron → refresh → ellipsis | 행 → refresh → ellipsis |
| 상태 표현 | 없음 | `.accessibilityValue("펼침/접힘")` |

### 영향 받는 코드

- `:109-117` chevron `Button` → `Image` + `.accessibilityHidden(true)`
- `:106-178` `sectionHeader`를 Button label로 재구성
- `:175-177` `.padding`·`.contentShape`·`.onTapGesture` → Button label 내부로 이동
- 행에 `.accessibilityValue`, `.accessibilityHint` 신설

## 5. 키보드 Tab navigation 흐름

```
[검색창]
  ↓
[서버 행 1]                 ← Enter: 펼침/접힘 (오프라인이면 재스캔)
  ↓
[refresh]                   ← Enter/Space: 포트 재스캔
  ↓
[⋯ 메뉴]                    ← Enter/Space: 메뉴 열기
  ↓
[포워딩 행 1 (active)]      ← Enter: 포워딩 끄기
  ↓
[브라우저 버튼]             ← Enter/Space: 기본 브라우저로 열기
  ↓
[포워딩 행 2 (idle)]        ← Enter: 포워딩 켜기 (브라우저 버튼 없음 → 다음 행으로)
  ↓
[서버 행 2] ...
```

Shift+Tab 역방향 흐름도 대칭.

## 6. 검증 시나리오 (수동, Xcode GUI)

자동화 테스트가 어려운 영역(접근성·키보드 라우팅)이므로 수동 체크리스트로 정의한다.

### 키보드 전용 (VoiceOver 끔)

- [ ] 메뉴바에서 PortBridge 열기 → 첫 Tab 시 검색창 또는 첫 서버 행에 포커스 (시각 포커스 링)
- [ ] Tab 흐름: `서버 행 → refresh → ⋯ → 포워딩 행 → 브라우저(active만) → 다음 행`
- [ ] 서버 행 포커스 후 Enter → 펼침/접힘 토글
- [ ] 포워딩 행(active) 포커스 후 Enter → 포워딩 끄기
- [ ] 브라우저 버튼 포커스 후 Space 또는 Enter → 기본 브라우저에서 `http://localhost:N` 열림
- [ ] Shift+Tab 역방향 정상

### VoiceOver (⌘F5)

- [ ] 서버 행 발화: "yhzion@host1, 펼침 / 접힘. 이중 탭하여 …"
- [ ] chevron이 별도 노드로 들리지 **않음**
- [ ] 포워딩 행 발화: "포트 8080, postgres, 포워딩 중. 이중 탭하여 포워딩 끄기"
- [ ] Active 행에서 다음 노드 = "브라우저에서 열기 버튼"
- [ ] Idle/Starting 행에서는 브라우저 노드 없음

### 시각 회귀

- [ ] 호버 시 OpenInBrowserButton 배경 idle→hover 전환 유지
- [ ] 호버 없어도 Active 행마다 브라우저 버튼 보임
- [ ] chevron 펼침/접힘 회전 애니메이션 유지
- [ ] 서버 행 마우스 클릭 → expand/collapse 정상 (Button 래핑 후에도)
- [ ] 좁은 폭(480pt) — 브라우저 버튼 잘리지 않음

### 회귀

- [ ] `⌘R` 전체 재스캔, `⌘N` 새 서버, `⌘⇧E` 모두 정상
- [ ] 에러 토스트 5초 자동 소멸 + 수동 닫기
- [ ] 포트 충돌 시트 입력 검증 정상

## 7. 비결정 사항 (구현 단계에서 검증)

- **Button + `.buttonStyle(.plain)` 호버 색상**: 현재 행에 별도 호버 배경이 없으므로 시각 변경이 의도되지 않는지 확인. 필요하면 `.background()`를 호버 상태에 따라 분기.
- **Menu 안의 ellipsis Tab 처리**: SwiftUI Menu의 trigger가 Button 트레잇과 충돌하지 않는지 실측 필요.
- **`@FocusState` 직접 사용 여부**: 1차 구현은 Button의 기본 focus 동작에 의존. 시각 포커스 링이 부족하면 `.focused()` 추가.

이 항목들은 implementation plan에서 코드로 검증한다.

## 8. 영향 범위

- 파일 2개: `PortBridge/Views/ForwardingRowView.swift`, `PortBridge/Views/ServerSectionView.swift`
- 모델·뷰모델·테스트 코드: 변경 없음
- 신규 의존성: 없음
- 새 토큰·아이콘: 없음 (기존 SF Symbols 그대로)
