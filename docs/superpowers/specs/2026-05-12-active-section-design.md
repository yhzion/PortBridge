# Active 포트 섹션 분리 — 디자인 문서

- **작성일**: 2026-05-12
- **상태**: Draft → 구현 대기
- **범위**: `PortListView` UX 고도화

## 1. 문제 정의

현재 `PortListView`는 스캔된 모든 포트를 단일 `List`에 평면으로 표시한다. 사용자가 어떤 포트를 포워딩 중인지 알아보려면 row를 하나씩 훑으며 녹색 dot을 찾아야 한다.

- 활성 포트와 비활성 포트의 시각적 위계가 약하다.
- 활성화 직후에도 row가 원래 자리에 머물러 "방금 켰는데 어디 있지" 하는 탐색 비용이 든다.
- 여러 개를 한 번에 끄는 정리 동작이 없다.

목표: **활성 포트를 상단의 별도 섹션으로 분리**하고, 토글 시 row가 그 섹션으로 자연스럽게 이동하는 우아한 UX를 제공한다.

## 2. 비목표 (Non-goals)

이번 작업에 포함하지 않는다:

- 활성화 지속 시간 표시 ("3분째 포워딩 중")
- 섹션 접기/펼치기 토글
- 드래그 reorder
- 다중 선택
- 호스트를 가로지르는 active 포트 통합 보기

## 3. 핵심 결정과 이유

### 3.1 컨테이너: `List` + `Section` 유지 (matched-geometry 미사용)

후보:
- **A. `ScrollView` + `LazyVStack` + `matchedGeometryEffect`** — row가 섹션 간 이동할 때 동일 view identity로 슬라이드.
- **B. `List` + `Section` + implicit `.animation`** — fade + position morph 자동.

**선택: B.**

이유:
- SwiftUI `List`는 row를 재활용/디퍼링하므로 `matchedGeometryEffect`의 namespace 공유가 안정적이지 않다 (jump-cut, 첫 프레임 튐).
- A를 택하면 macOS native 키보드 네비게이션·선택 하이라이트·`.listStyle` 변종을 잃는다.
- 보통 10~30개 row 규모에서 `.animation(.spring, value: ...)` 으로 충분히 우아한 reorder가 가능하다.
- 이번 한 가지 기능 때문에 native List 인프라를 포기할 가치는 없다고 판단.

### 3.2 활성 row 식별 범위: `.active` + `.starting` + `.error`

활성 섹션에 포함하는 상태:
- `.starting` — 켜는 중. 사용자가 "어디 갔지" 헤매지 않게 즉시 active 섹션으로.
- `.active` — 정상 포워딩 중.
- `.error` — 활성 row에 빨간 점으로 남겨두고 클릭으로 재시도. 다른 곳으로 옮기면 사용자가 잃어버린다.

`.idle` / forwarding 없음 → inactive 섹션.

### 3.3 정렬: 활성화 시각 역순

`activatedAt: [UUID: Date]` 딕셔너리를 ViewModel에 추가. `startForwarding`에서 placeholder를 append할 때 채우고, off 시 삭제. 활성 섹션 내부는 최근에 켠 것이 위.

이유: 사용자가 방금 켠 포트가 시야에 들어오는 게 가장 자주 필요한 상호작용.

### 3.4 검색어가 active 섹션에 미치는 영향: **무시한다**

검색어가 입력되어도 active 섹션은 항상 전부 보여준다. inactive 섹션만 필터링.

이유: 사용자가 켜둔 포워딩을 검색어 때문에 시야에서 잃는 것은 안전상 손해. 활성 row는 항상 보여야 한다.

### 3.5 "모두 끄기"는 confirmation 없이 즉시

이유: 현재 단일 row 토글도 즉시 작동 (confirmation 없음). 동일한 UX 일관성을 유지. 실수는 다시 켜면 복구되므로 비가역적이지 않다.

## 4. 아키텍처

```
PortListView
├── (state)   vm.ports, vm.forwardings              ← 기존
├── (state)   vm.activatedAt: [UUID: Date]          ← 신규
├── (derived) vm.activeForwardedPorts               ← 신규
├── (derived) vm.inactivePorts                      ← 신규
└── body
    ├── SearchField (기존)
    └── List
        ├── Section { ActiveSectionHeader }         ← 신규 컴포넌트
        │     └── ForwardingRowView(isActive: true) × N
        └── Section { AllPortsSectionHeader }
              └── ForwardingRowView(isActive: false) × M
```

## 5. 컴포넌트 변경

### 5.1 `AppViewModel`

신규 상태:

```swift
private var activatedAt: [UUID: Date] = [:]
```

신규 derived:

```swift
var activeForwardedPorts: [(port: RemotePort, forwarding: Forwarding)] {
    let active = forwardings.filter { fw in
        guard fw.host == selectedHost?.name else { return false }
        switch fw.state {
        case .active, .starting, .error: return true
        case .idle: return false
        }
    }
    return active
        .compactMap { fw in
            ports.first(where: { $0.port == fw.remotePort }).map { ($0, fw) }
        }
        .sorted {
            activatedAt[$0.forwarding.id, default: .distantPast]
            > activatedAt[$1.forwarding.id, default: .distantPast]
        }
}

var inactivePorts: [RemotePort] {
    let activePortNums = Set(activeForwardedPorts.map { $0.port.port })
    return filteredPorts.filter { !activePortNums.contains($0.port) }
}
```

기존 `startForwarding`을 수정 (현재 `TunnelManager.start`는 새 `Forwarding`을 반환하므로 placeholder id ≠ 성공 시 id):

- placeholder append 직후: `activatedAt[placeholderID] = Date()`.
- `tunnels.start` 성공 시: `activatedAt[fw.id] = activatedAt.removeValue(forKey: placeholderID) ?? Date()`.
- 포트 충돌(`forwardingDiedEarly` + "address already in use"): `activatedAt[placeholderID] = nil` (conflict sheet 해결 후 재시도 시 새 placeholder가 다시 시각을 기록).
- 그 외 실패로 placeholder 제거 시: `activatedAt[placeholderID] = nil`.

기존 `toggleForwarding`의 off 분기:
- `activatedAt[existing.id] = nil`.

`tunnelDidExit` (error 진입):
- `forwardings[idx].state`만 변경되어 id가 유지됨 → `activatedAt`은 건드리지 않음 (정렬 위치 유지).

신규 메서드:

```swift
func stopAllForCurrentHost() {
    guard let host = selectedHost else { return }
    let mine = forwardings.filter { $0.host == host.name }
    for fw in mine {
        tunnels.stop(fw.id)
        activatedAt[fw.id] = nil
    }
    forwardings.removeAll { $0.host == host.name }
}
```

### 5.2 `PortListView`

`List`를 두 `Section`으로 재구성:

```swift
List {
    if !vm.activeForwardedPorts.isEmpty {
        Section {
            ForEach(vm.activeForwardedPorts, id: \.port.id) { entry in
                ForwardingRowView(
                    port: entry.port,
                    forwarding: entry.forwarding,
                    isActive: true,
                    onToggle: { Task { await vm.toggleForwarding(for: entry.port) } }
                )
            }
        } header: {
            ActiveSectionHeader(
                count: vm.activeForwardedPorts.count,
                onStopAll: { vm.stopAllForCurrentHost() }
            )
        }
    }
    Section {
        ForEach(vm.inactivePorts) { port in
            ForwardingRowView(
                port: port,
                forwarding: nil,
                isActive: false,
                onToggle: { Task { await vm.toggleForwarding(for: port) } }
            )
        }
    } header: {
        AllPortsSectionHeader(count: vm.inactivePorts.count)
    }
}
.animation(
    .spring(response: 0.4, dampingFraction: 0.85),
    value: vm.activeForwardedPorts.map(\.port.id)
)
```

기존 "검색된 포트 N개 / 총 M개" 카운트 라인은 제거 — 각 섹션 헤더가 그 정보를 전달.

### 5.3 `ForwardingRowView`

신규 prop `isActive: Bool` 추가. body에 다음만 추가:

```swift
.background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
.overlay(alignment: .leading) {
    if isActive {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 3)
    }
}
```

기존 dot/text/safari 버튼 로직은 변경 없음.

### 5.4 `ActiveSectionHeader` (신규)

```swift
struct ActiveSectionHeader: View {
    let count: Int
    let onStopAll: () -> Void

    var body: some View {
        HStack {
            Text("포워딩 중 · \(count)")
            Spacer()
            Button("모두 끄기", action: onStopAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
```

### 5.5 `AllPortsSectionHeader` (신규)

```swift
struct AllPortsSectionHeader: View {
    let count: Int
    var body: some View {
        Text("전체 포트 · \(count)")
    }
}
```

## 6. 데이터/이벤트 플로우

켜기:
```
[사용자가 inactive row 클릭]
        ↓
vm.toggleForwarding(for:)
        ↓
forwardings.append(placeholder(state: .starting))
activatedAt[placeholderID] = Date()
        ↓
[activeForwardedPorts 1개 증가]
[inactivePorts에서 해당 port 제거]
        ↓
SwiftUI가 .spring 으로 reorder
        ↓
tunnels.start 완료 → state .active 로 교체
        ↓
status dot이 progress → green
```

끄기:
```
[사용자가 active row 클릭]
        ↓
forwardings.removeAll(matching)
activatedAt[id] = nil
        ↓
[activeForwardedPorts 감소, inactivePorts 증가]
        ↓
.spring reorder
```

모두 끄기:
```
[사용자가 "모두 끄기" 클릭]
        ↓
vm.stopAllForCurrentHost()
        ↓
host의 모든 forwarding stop + activatedAt 정리
        ↓
[activeForwardedPorts 비워짐 → active 섹션 사라짐]
[inactivePorts에 모두 합류]
        ↓
.spring reorder + 섹션 헤더 fade out
```

## 7. 엣지 케이스

| 케이스 | 동작 |
|---|---|
| 검색어 입력 + 활성화 | active 섹션은 검색과 무관하게 항상 표시. inactive만 필터. |
| 호스트 전환 | 다른 호스트 forwarding은 화면에 안 보임 (기존 로직). active 섹션도 자연히 비워짐. |
| 활성 0개 | active 섹션 헤더 전체를 숨김 (`if !empty`). inactive만 표시되어 기존 외형과 거의 동일. |
| "모두 끄기" 클릭 | 현재 호스트의 모든 forwarding을 즉시 stop. confirmation 없음. |
| `.error` 상태 | active 섹션에 빨간 점으로 남음. 클릭 시 재시도 (기존). |
| 스캔으로 active 포트가 사라진 경우 | `activeForwardedPorts`의 compactMap에서 port 매치 실패 시 해당 row 사라짐. 드물지만 가능 — 별도 cleanup은 범위 밖. |
| App quit | 기존 `shutdownAll()` 그대로 작동. `activatedAt`은 process 종료와 함께 사라짐. |

## 8. 테스트 전략

`PortBridgeTests`에 `AppViewModel+ActiveSectionTests.swift` 신규:

- `activeForwardedPorts`가 `.starting/.active/.error`를 포함하고 `.idle`은 제외하는지
- inactive 섹션이 active 포트 번호를 제거하는지
- `activatedAt` 정렬: 늦게 켠 것이 위
- `stopAllForCurrentHost()` 가 현재 호스트의 것만 끄는지 (다른 호스트 forwarding은 유지)
- 호스트 전환 시 active 컬렉션이 비는지
- 검색어 입력이 active 섹션에 영향 없는지, inactive만 필터링되는지

애니메이션 자체는 단위테스트 어려움 — 수동 QA로 다룸.

수동 QA 체크리스트:
1. 스캔 후 inactive row 1개 토글 → active 섹션 생성 + row가 위로 슬라이드
2. 추가 2개 토글 → 최근 켠 것이 위에 쌓이는지
3. 검색어 입력 → active 섹션 그대로, inactive만 필터
4. "모두 끄기" 클릭 → 모두 inactive로 슬라이드 + active 섹션 사라짐
5. error 상태 진입 → 빨간 점으로 active 섹션 잔류, 클릭 시 재시도
6. 라이트/다크 모드에서 accent tint 가독성 확인

## 9. 마이그레이션·호환성

- 외부 API/상태 파일 없음. UI 한정.
- 기존 `forwardings`/`ports` 모델 변경 없음 — `activatedAt`만 ViewModel 내부 추가.
- 기존 view 단 테스트가 있다면 섹션 헤더 추가로 인한 hierarchy 단언은 갱신 필요.

## 10. 결정 요약

| 항목 | 결정 |
|---|---|
| 컨테이너 | `List` + `Section` |
| 애니메이션 | `.animation(.spring, value: activeIds)` |
| 활성 강조 | row 배경 tint + 좌측 3px accent bar |
| 헤더 | "포워딩 중 · N" + 우측 "모두 끄기" / "전체 포트 · M" |
| 활성 포함 상태 | `.starting`, `.active`, `.error` |
| 정렬 | `activatedAt` 역순 (최근에 켠 것이 위) |
| 검색 영향 | active 섹션 무시, inactive만 필터 |
| "모두 끄기" | confirmation 없이 즉시 실행 |
