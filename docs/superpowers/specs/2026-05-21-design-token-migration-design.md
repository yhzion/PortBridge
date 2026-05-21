# 매직 넘버 → `PBLayout` 토큰 마이그레이션

## 1. 배경

`PortBridge/Views/Layout.swift`에 디자인 토큰(`PBLayout.Space`, `PBLayout.Radius`)이 정의되어 있으나, 기존 뷰 코드의 매직 넘버(`spacing: 8`, `cornerRadius: 6`, `.padding(.vertical, 4)` 등)는 토큰을 참조하지 않는다. 이 작업은 **이미 정의된 토큰과 정확히 일치하는 매직 넘버만** 토큰 참조로 교체한다.

`Color.PB` / `PBLayout`의 일관된 철학 — "시스템 시맨틱·기존 추상화를 가능한 한 활용, hex/매직넘버는 의도가 분명한 곳에서만 박는다" — 와 일치한다.

## 2. 범위

### 포함

| Before | After | 컨텍스트 |
|---|---|---|
| `4` | `PBLayout.Space.s1` | `VStack`/`HStack`의 `spacing:`, `.padding(_:_, 4)` |
| `8` | `PBLayout.Space.s2` | 동일 |
| `12` | `PBLayout.Space.s3` | 동일. 단 `s3`는 row vertical padding 외 group vertical 간격에도 쓰임 (예: `ContentView:113`, `ServerListView:82, 102`). 토큰 문서는 둘 다 포괄하도록 broaden됨. |
| `16` | `PBLayout.Space.s4` | 동일 |
| `6` | `PBLayout.Radius.sm` | `RoundedRectangle(cornerRadius: 6)` (직접 인스턴스, `.background(_, in: ...)`, `.contentShape(...)` 호출 모두 포함). 칩·배지·라벨뿐 아니라 `ServerMonogram` 같은 작은 둥근 컨테이너에도 적용. |

### 명시적 제외

다음은 이번 작업에서 손대지 않는다:

- **숫자는 일치하나 의미 도메인이 다른 경우**: `padding 6`(7건). cornerRadius의 `6`은 `Radius.sm`이지만, padding의 `6`은 토큰에 없으므로 그대로 둔다. 같은 숫자라도 도메인이 다르면 다르게 처리한다.
- **토큰에 없는 outlier 값**:
  - `spacing: 0, 1, 6, 10, 24`
  - `cornerRadius: 4, 5`
  - `padding 1, 2, 6, 7, 10, 24`
- **시맨틱 의도가 별도인 호출**: `.padding()`(no-arg, 시스템 디폴트), `.padding(.horizontal)`(no-value).
- **spacing/radius 도메인이 아닌 매직 넘버**: `frame(width:height:)`(컴포넌트 크기), `lineWidth:`(stroke 두께), `Color.opacity(_:)`(투명도), font size.
- **`Color.PB` 영역**: 이미 토큰화됨. 추가 정리 없음.

## 3. 변경 파일 및 예상 건수

| 파일 | spacing | cornerRadius | padding | 합 |
|---|---|---|---|---|
| `PortBridge/ContentView.swift` | 2 | 2 | 1 | 5 |
| `PortBridge/Views/ServerSectionView.swift` | 8 | 2 | 5 | 15 |
| `PortBridge/Views/ServerListView.swift` | 3 | 0 | 4 | 7 |
| `PortBridge/Views/ForwardingRowView.swift` | 1 | 3 | 3 | 7 |
| `PortBridge/Views/AddServerSheet.swift` | 1 | 0 | 0 | 1 |
| `PortBridge/Views/MenuBarIconView.swift` | 0 | 0 | 0 | 0 |
| **합계** | **15** | **7** | **13** | **35** |

토큰별 분포 (cross-check): `Space.s1(4)` 12건 · `Space.s2(8)` 10건 · `Space.s3(12)` 4건 · `Space.s4(16)` 2건 · `Radius.sm(6)` 7건 = **35건**.

`MenuBarIconView`의 `spacing: 24`는 토큰 없음(outlier)이므로 이 작업에서 손대지 않는다.

## 4. 절차

1. 파일별로 순회한다. 각 파일에서:
   - 정확 일치하는 매직 넘버를 토큰으로 교체.
   - 변경 직후 `xcodebuild -scheme PortBridge -destination 'platform=macOS' build`로 컴파일 검증.
2. 전체 완료 후:
   - SwiftLint·SwiftFormat 통과 확인(`.swiftlint.yml`, `.swiftformat` 설정 기존 유지).
   - `git diff` 자체 점검: outlier가 실수로 포함되지 않았는지.
3. UI 시각 검증은 **CLI로 불가**(메모리: xcodebuild test LaunchServices 이슈). 사용자가 Xcode GUI 실행 또는 ⌘U로 한 번 눈으로 확인.

## 5. 커밋 전략

- **단일 커밋**으로 묶는다. 35건이 모두 같은 의도("토큰화")이므로 git blame에 한 줄로 남는 게 자연스럽다.
- 커밋 메시지:
  ```
  refactor(views): swap exact-match magic numbers to PBLayout tokens

  - 4/8/12/16 (spacing, padding) → PBLayout.Space.s1..s4
  - cornerRadius 6 → PBLayout.Radius.sm
  - outlier 값(padding 6, cornerRadius 5 등)은 정확 일치 정책에 따라 보존
  ```

## 6. 위험과 완화

| 위험 | 완화 |
|---|---|
| outlier(특히 `padding 6` 6건: `ContentView:66`, `ServerListView:205`, `ServerSectionView:157, 197, 378, 396`)가 토큰화되지 않아 "왜 어떤 6은 토큰이고 어떤 6은 아닌가" 의문이 코드에 남음 | 본 spec과 커밋 메시지에 "정확 일치 정책 + 도메인 분리"를 명시. 후속 의사결정 항목으로 분리. |
| 자동 치환 실수로 의도 외 값까지 변경 | 각 Edit은 충분히 긴 context(주변 줄 포함)로 unique match 강제. 파일별 빌드로 즉시 회귀 검출. |
| 빌드 통과 ≠ 런타임 외관 동등 보장 | 수치 동등성으로 픽셀-퍼펙트 1차 보증. 추가로 사용자가 Xcode GUI에서 1회 실행해 active/all-servers 섹션, 즐겨찾기 row, 검색 입력 등 토큰이 닿은 영역의 외관을 육안 확인. SwiftUI Preview가 있다면 함께 점검. |
| `.swiftformat` / `.swiftlint.yml` 규칙이 토큰 표현을 다시 리터럴로 되돌릴 가능성 | Codex 사전 검증 결과 현재 규칙에는 해당 항목 없음(no_magic_numbers 류 비활성). 마이그레이션 후 `swiftformat --lint .`와 `swiftlint` 모두 통과 확인. |
| 동시 진행 중인 다른 브랜치/PR과 같은 줄을 만져 merge conflict | 35건이 6개 파일에 흩어져 있어 conflict 표면이 작지만, 머지 전 main과 rebase. 충돌 발생 시 토큰 참조를 우선 유지하고 outlier 값은 main 측 변경에 따른다. |

## 7. 비범위 (후속 결정 항목)

다음은 의도적으로 이 작업에서 제외했으며, 별도 의사결정이 필요하다:

- `padding: 6`(6건)의 토큰화 — 토큰 확장(`Space.s1half = 6`?) 또는 기존 토큰으로 정렬(`6→s2(8)`)
- `cornerRadius: 4, 5`의 토큰화 — `Radius.xs/xsm` 추가 또는 `sm(6)`으로 정렬
- 색/투명도 매직 넘버(`Color.red.opacity(0.08)` 등)의 토큰화
- `lineWidth: 1`, `lineWidth: 0.5` 같은 hairline 두께 토큰화
- 미사용 토큰(`Radius.md/lg/xl`, `Space.s5/s6`) 정리 또는 활용 시점
