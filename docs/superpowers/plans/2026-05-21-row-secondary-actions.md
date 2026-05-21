# 행 내부 부 동작의 접근성 통합 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** UI/UX 리뷰 #3·#5 항목을 해결 — `ForwardingRowView`와 `ServerSectionView` 행 내부의 부 동작(OpenInBrowserButton, chevron)을 키보드·VoiceOver 사용자도 도달 가능하도록 접근성 트리·Tab navigation을 정리한다.

**Architecture:** 두 행 모두 전체 HStack을 `Button` 라벨로 감싸 macOS-native Tab focus·Enter·Space 처리를 얻는다. 시각 단서(chevron)는 `.accessibilityHidden(true)`로 트리에서 제거하고, 부 동작 버튼(OpenInBrowserButton)은 호버 의존을 끊어 상태가 의미 있는 동안 항상 노출한다.

**Tech Stack:** SwiftUI (macOS 14+), AppKit interop, Xcode 16 빌드 시스템.

**Spec:** `docs/superpowers/specs/2026-05-21-row-secondary-actions-design.md` (커밋 `c5f293f`)

---

## 사전 상태

- **워크트리**: `worktree-wcag-input-border` (base: `origin/main` @ `6f790bc`, Menu Bar Extras 머지 포함)
- **선행 main 의존성**: `437cbfd feat(view): add leading star button to ForwardingRowView` — `ForwardingRowView`에 `isFavorite`·`onFavoriteToggle` 필드와 leading star Button(첫 자식)이 추가됨. **본 plan은 이 star Button을 보존하면서 동작하도록 "본문 영역만 outer Button으로 감싸는" 옵션 A 패턴을 적용한다**
- **선행 미커밋 변경**: 워킹트리에 다음 변경이 staged 안 됨 — Task 0에서 처리
  - `PortBridge/Views/DesignTokens.swift` (WCAG inputBorder 라이트 톤 강화, 리뷰 항목 1번)
  - `PortBridge/ContentView.swift` (PortConflictSheet 입력 검증, 리뷰 항목 2번)
- **빌드 명령**: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build`
- **메모리 노트**: CLI 단위 테스트 러너는 환경 이슈로 불안정 (`xcodebuild-test-launch-issue.md`) — Xcode GUI ⌘U 또는 수동 검증으로 대체

## 파일 구조

이번 PR이 손대는 파일 (전부 기존 파일):

| 파일 | 책임 | Task |
|---|---|---|
| `PortBridge/Views/DesignTokens.swift` | 디자인 토큰 (이미 수정됨) | Task 0 |
| `PortBridge/ContentView.swift` | PortConflictSheet (이미 수정됨) | Task 0 |
| `PortBridge/Views/ForwardingRowView.swift` | 포워딩 행 — Button 래핑, OpenInBrowserButton 노출 정책, 접근성 트리 | Task 1, 2, 3 |
| `PortBridge/Views/ServerSectionView.swift` | 서버 섹션 헤더 — chevron 격하, 행 Button 래핑, 접근성 트리 | Task 4, 5, 6 |

신규 파일 없음. 모델·뷰모델·테스트 코드 변경 없음.

---

## Task 0: 선행 작업 커밋 (리뷰 항목 1·2번 정리)

**목적:** 본 작업 시작 전 워킹트리의 미커밋 변경을 명확한 커밋으로 분리. 이후 3·5번 작업 커밋과 섞이지 않게.

**Files:**
- Commit: `PortBridge/Views/DesignTokens.swift`
- Commit: `PortBridge/ContentView.swift`

- [ ] **Step 0.1: 미커밋 변경 상태 확인**

Run: `git status --short PortBridge/Views/DesignTokens.swift PortBridge/ContentView.swift`
Expected:
```
 M PortBridge/ContentView.swift
 M PortBridge/Views/DesignTokens.swift
```

- [ ] **Step 0.2: WCAG inputBorder 변경만 staging**

```bash
git add PortBridge/Views/DesignTokens.swift
git diff --cached --stat
```
Expected: `1 file changed, 3 insertions(+), 2 deletions(-)`

- [ ] **Step 0.3: 1번 커밋**

```bash
git commit -m "$(cat <<'EOF'
fix(a11y): meet WCAG 1.4.11 for input border in light mode

Light-mode inputBorder #AEAEB2 vs white was 2.21:1 (below 3:1).
Switch to Apple systemGray (#8E8E93) — 3.26:1 against
textBackgroundColor. Dark-mode token unchanged (already 3.33:1).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 0.4: PortConflictSheet 검증 staging**

```bash
git add PortBridge/ContentView.swift
git diff --cached --stat
```
Expected: `1 file changed, ~30 insertions(+), 4 deletions(-)`

- [ ] **Step 0.5: 2번 커밋**

```bash
git commit -m "$(cat <<'EOF'
fix(ui): validate local port in PortConflictSheet

Add range check (1–65535) and reject the conflicted port itself.
Show inline red caption and disable "연결" button on invalid input
— fixes silent no-op when user pressed Enter with an empty or
out-of-range value.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 0.6: 빌드 검증**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

---

## Task 1: ForwardingRowView 본문 영역을 Button으로 래핑 (옵션 A)

**목적:** star Button을 보존하면서 행 본문(statusIndicator·포트·이름·브라우저)을 별도 outer Button으로 감싼다. 결과: star = Tab stop 1, 본문 = Tab stop 2, 브라우저 = Tab stop 3.

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift:59-122`

- [ ] **Step 1.1: 현재 body 구조 확인**

Run: `sed -n '59,122p' PortBridge/Views/ForwardingRowView.swift`
Expected: leading star Button, statusIndicator, port column, VStack, Spacer, OpenInBrowserButton (hover gated), error icon — 모두 `HStack` 단일 자식. 외부에 `.onTapGesture { onToggle() }`와 `.accessibilityElement(.combine)`.

- [ ] **Step 1.2: body 전체를 옵션 A 구조로 재작성**

`var body: some View { ... }` 블록 전체를 다음으로 교체:

```swift
var body: some View {
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

        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 10) {
                statusIndicator
                    .frame(width: 18, height: 18)

                if showPortColumn {
                    Text(verbatim: ":\(port.port)")
                        .font(.system(.body, design: .monospaced).bold())
                        .monospacedDigit()
                        .foregroundStyle(isErrorState ? .red : isActive ? .green : .primary)
                        .frame(minWidth: 48, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(rightPrimary)
                        .font(.caption)
                        .foregroundStyle(rightPrimaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let secondary = rightSecondary {
                        Text(secondary)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if isActive, let local = forwarding?.localPort, isRowHovering {
                    OpenInBrowserButton(localPort: local)
                }

                if case .error(let msg) = forwarding?.state {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(String(msg))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .help(forwarding?.state == .active ? "클릭해 포워딩 끄기" : "클릭해 포워딩 켜기")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(forwarding?.state == .active ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기")
        .accessibilityAddTraits(.isButton)
    }
    .padding(.vertical, 4)
    .onHover { isRowHovering = $0 }
}
```

변경 요점:
- **leading star Button은 그대로 보존** — outer HStack의 첫 자식, 독립 Tab stop
- **본문 영역만 두 번째 `Button(action: onToggle)`로 감쌈** — chevron 충돌 방지
- 기존 `.onTapGesture { ... onToggle() }` 제거 — outer 본문 Button action으로 대체
- `.disabled(isStarting)`이 기존 `guard !isStarting else { return }` 역할 대신함
- `.padding(.vertical, 4)`·`.onHover`는 outer HStack 레벨로 이동
- `.help` / `.accessibilityElement` / `.accessibilityLabel` / `.accessibilityHint` / `.accessibilityAddTraits` 묶음은 본문 Button에 부착 (Task 3에서 `.contain`으로 바꾸고 `.isButton` 제거)
- `OpenInBrowserButton` 노출 조건은 이 Task에서는 **그대로** 유지 (Task 2에서 변경)

- [ ] **Step 1.3: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 1.4: Xcode GUI 빠른 회귀 점검**

수동 (≤ 2분):
- Xcode ⌘R로 실행 → 메뉴바 PortBridge 클릭
- Active 포워딩 행을 마우스 클릭 → 포워딩 토글 동작 확인
- starting 상태 행은 클릭해도 무반응(`.disabled`) 확인
- 호버 시 OpenInBrowserButton 노출 변화 그대로

- [ ] **Step 1.5: 커밋**

```bash
git add PortBridge/Views/ForwardingRowView.swift
git commit -m "$(cat <<'EOF'
refactor(forwarding-row): wrap body region in Button (keep star)

Split the row into two sibling Buttons: the existing star Button
remains a leading Tab stop, and a new Button(action: onToggle)
wraps the body region (status, port, name, browser). Replaces
the row-wide .onTapGesture with native Button handling and adds
.disabled(isStarting) in place of the manual guard.

No visual or VoiceOver tree change yet; accessibility refinements
follow in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: OpenInBrowserButton을 Active 시 항상 노출

**목적:** 호버 의존을 끊어 키보드·VoiceOver 사용자도 브라우저 버튼에 도달 가능하게 한다.

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift` — Task 1 후 OpenInBrowserButton 조건문 1줄

- [ ] **Step 2.1: 조건문에서 isRowHovering 제거**

`ForwardingRowView.swift` body 안의 다음 라인을 찾아 수정:

변경 전:
```swift
if isActive, let local = forwarding?.localPort, isRowHovering {
    OpenInBrowserButton(localPort: local)
}
```

변경 후:
```swift
if isActive, let local = forwarding?.localPort {
    OpenInBrowserButton(localPort: local)
}
```

`isRowHovering` state는 그대로 유지(향후 행 hover 배경 효과에 활용 여지). `.onHover { isRowHovering = $0 }`도 유지.

- [ ] **Step 2.2: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2.3: Xcode GUI 수동 점검 (시각)**

- Active 포워딩 행에 마우스를 올리지 않아도 우측에 "[↗ 브라우저에서 열기]" 칩이 보이는지 확인
- Idle / Starting / Error 행에는 칩이 보이지 **않는지** 확인
- 호버 시 칩 배경이 idle→hover로 부드럽게 전환되는지 확인(기존 동작)
- 좁은 폭(약 480pt)에서 칩이 잘리지 않고 우측 정렬 유지

- [ ] **Step 2.4: 커밋**

```bash
git add PortBridge/Views/ForwardingRowView.swift
git commit -m "$(cat <<'EOF'
fix(a11y): always show OpenInBrowserButton on active rows

Removing the isRowHovering gate means keyboard and VoiceOver users
can now reach the browser action. Hover state is retained for the
existing background-fill effect on the button itself.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ForwardingRowView 본문 Button 접근성 트리 재정리

**목적:** 본문 Button의 자식 OpenInBrowserButton이 VoiceOver에 별도 노드로 노출되도록 `.combine` → `.contain`. 본문이 SwiftUI Button이므로 `.isButton` 트레잇은 자동 부여 — 명시 제거.

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift` — 본문 `Button(action: onToggle)`의 accessibility modifier 묶음

- [ ] **Step 3.1: 본문 Button의 accessibility modifier 교체**

다음 modifier 묶음을 (Task 1.2에서 본문 Button에 부착해둔 묶음):

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel(accessibilityLabel)
.accessibilityHint(forwarding?.state == .active ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기")
.accessibilityAddTraits(.isButton)
```

다음으로 교체:

```swift
.accessibilityElement(children: .contain)
.accessibilityLabel(accessibilityLabel)  // 기존 private computed property (`accessibilityLabel`, 현 코드 :140-146) 그대로 사용
.accessibilityHint(forwarding?.state == .active ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기")
```

변경 요점:
- `.combine` → `.contain`: 자식 OpenInBrowserButton이 별도 노드로 노출됨
- `.accessibilityAddTraits(.isButton)` 제거: 외부 본문 Button이 자동 부여
- star Button의 accessibility(별도 label·help)는 영향 없음 — outer HStack의 형제이므로 독립 노드

- [ ] **Step 3.2: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3.3: VoiceOver 수동 점검**

VoiceOver ⌘F5 ON, Active 포워딩 행 영역 흐름:
- star 노드 발화: "즐겨찾기 추가 / 해제 버튼"
- 본문 노드 발화: "포트 8080, [서버명] · 포워딩 중, … 버튼. 이중 탭하여 포워딩 끄기"
- 다음 노드: "브라우저에서 열기 버튼"
- Idle/Starting/Error 행 본문 다음 → 브라우저 노드 **없음**, 곧바로 다음 행 star

VoiceOver ⌘F5 OFF (키보드만):
- Tab 흐름: `star → 본문 → 브라우저(active) → 다음 행 star …`
- 각 Tab stop에 시각 포커스 링이 보이는지 확인
- 본문 포커스 + Enter → 토글
- 브라우저 포커스 + Space/Enter → 브라우저 열림

- [ ] **Step 3.4: 커밋**

```bash
git add PortBridge/Views/ForwardingRowView.swift
git commit -m "$(cat <<'EOF'
feat(a11y): expose OpenInBrowserButton as separate VO node

Switch row accessibilityElement from .combine to .contain so the
browser button is reachable via VoiceOver rotor and Tab key.
Drop the now-redundant .isButton trait — the outer Button supplies
it automatically.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ServerSectionView chevron을 시각 단서로 격하

**목적:** chevron이 별도 VoiceOver 버튼 노드로 노출되어 작은 탭 영역을 형성하는 문제 해소. 시각적으로는 그대로지만 접근성 트리에서 사라진다.

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift:121-134` (라인 번호는 main `6f790bc` 기준)

- [ ] **Step 4.1: chevron Button → Image 교체**

다음 블록:

```swift
if !isOffline {
    Button(action: toggleExpandedAnimated) {
        Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 12)
            .transaction { $0.animation = nil }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(section.isExpanded ? "접기" : "펼치기")
} else {
    // 12px 자리 비움 — 다른 행과 가로 정렬 유지
    Color.clear.frame(width: 12, height: 12)
}
```

다음으로 교체:

```swift
if !isOffline {
    Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 12)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
} else {
    // 12px 자리 비움 — 다른 행과 가로 정렬 유지
    Color.clear.frame(width: 12, height: 12)
}
```

변경 요점:
- `Button(action: toggleExpandedAnimated) { Image(...) } .buttonStyle(.plain)` → 단순 `Image(...)`
- `.accessibilityLabel("접기/펼치기")` → `.accessibilityHidden(true)`
- `toggleExpandedAnimated()` 메서드는 다음 Task에서 행 Button action에 연결될 때까지 일시적으로 호출되지 않음 — 일단 유지 (다음 Task에서 사용)

이 시점에 chevron 클릭이 동작하지 않게 되지만, 행 전체 `.onTapGesture { handleRowTap() }`(`:177`)이 아직 살아 있어 행 자체로는 펼침/접힘 가능. Task 5에서 정식 행 Button으로 통합.

- [ ] **Step 4.2: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4.3: 동작 확인**

수동 (≤ 1분):
- 서버 행을 (chevron이 아닌 가운데 영역) 클릭 → 펼침/접힘 정상
- chevron 자체 클릭은 행 onTapGesture가 부모에서 받으므로 여전히 동작 (시각적으로 같음)
- VoiceOver ⌘F5 ON → 서버 행 발화 시 "접기/펼치기 버튼" 노드가 들리지 **않는지** 확인

- [ ] **Step 4.4: 커밋**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "$(cat <<'EOF'
refactor(server-section): demote chevron to visual cue

The 12pt chevron Button was duplicated by the row's onTapGesture,
exposing two VoiceOver nodes for the same expand/collapse action
while giving keyboard users a tiny tap target. Replace with a
plain Image marked .accessibilityHidden(true); the row will absorb
the disclosure semantics in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: ServerSectionView 행을 Button으로 래핑

**목적:** ForwardingRow와 동일하게 행 전체를 Button으로 감싸 키보드 Tab stop + Enter/Space 처리를 얻는다.

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift:119-191` (라인 번호는 main `6f790bc` 기준)

- [ ] **Step 5.1: 현재 sectionHeader 구조 확인**

Run: `sed -n '119,191p' PortBridge/Views/ServerSectionView.swift`
Expected: `private var sectionHeader: some View { HStack(spacing: 8) { ... } .padding(.vertical, 6) .contentShape(Rectangle()) .onTapGesture { handleRowTap() } }`

- [ ] **Step 5.2: sectionHeader를 옵션 A 구조로 재작성**

ForwardingRowView와 동일한 분리 원칙: **본문 영역(chevron + monogram + 이름 + count badge)만** 첫 번째 `Button(action: handleRowTap)`으로 감싸고, **refresh와 ellipsis는 outer HStack의 형제 Button**으로 유지.

`sectionHeader` computed property 전체를 다음으로 교체:

```swift
private var sectionHeader: some View {
    HStack(spacing: 8) {
        Button(action: handleRowTap) {
            HStack(spacing: 8) {
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

                ServerMonogram(server: section.server, status: statusDot, dimmed: isOffline)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryLabel)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOffline ? .secondary : .primary)
                        .lineLimit(1)
                    Text(secondaryLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if activeCount > 0 && !isOffline {
                    Text(verbatim: "\(activeCount)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.PB.accentBadgeBg, in: Capsule())
                        .help("이 서버에서 포워딩 중인 포트 수")
                        .accessibilityLabel(activeCountAccessibility)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if case .scanning = section.scanState {
            ProgressView().controlSize(.small)
        } else if !isOffline {
            Button { Task { await section.scan() } } label: {
                Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("\(primaryLabel) 포트 재스캔")
            .accessibilityLabel("\(primaryLabel) 포트 재스캔")
        }

        Menu {
            Button("편집…", action: onEdit)
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis").font(.body).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .accessibilityLabel("\(primaryLabel) 더보기")
    }
    .padding(.vertical, 6)
}
```

변경 요점:
- **outer HStack** 유지. 그 안에 세 형제: 본문 Button / refresh Button(또는 ProgressView) / Menu
- **본문 Button**이 chevron·monogram·이름·badge를 감쌈 — Tab stop 1
- refresh와 ellipsis Menu는 본문 Button **바깥**에 있어 독립 Tab stop — 부모 Button과 hit testing 충돌 회피
- 외부의 `.onTapGesture { handleRowTap() }` 제거 — 본문 Button action으로 대체
- `.padding(.vertical, 6)`는 outer HStack 레벨, `.contentShape(Rectangle())`는 본문 Button 안 HStack에
- 접근성 modifier는 Task 6에서 본문 Button에 부착

- [ ] **Step 5.3: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5.4: 본문/형제 Button 분리 동작 검증**

옵션 A에서는 refresh·ellipsis가 본문 Button **바깥**의 형제이므로 hit testing 충돌은 구조적으로 발생하지 않아야 함. 수동 점검:
- 본문 영역(chevron + monogram + 이름) 클릭 → 펼침/접힘
- refresh 버튼 클릭 → 재스캔만 트리거, 펼침/접힘 **안 일어남**
- ellipsis 메뉴 클릭 → 메뉴 열림, 펼침/접힘 **안 일어남**
- 만약 outer HStack 사이 빈 공간(spacing) 클릭 시 무반응이라면 정상 — 본문 영역도 형제도 아니므로

- [ ] **Step 5.5: Tab focus 링 가시성 (스펙 §7 비결정 사항)**

수동 점검:
- Tab으로 서버 행 포커스 시 시각 포커스 링이 보이는지 확인
- 안 보이면 `Button(action: handleRowTap) { ... }` 라벨 안 HStack에 `.overlay { focused ring }`를 `@FocusState`로 추가하는 후속 보강 검토 (지금은 기록만)

- [ ] **Step 5.6: 커밋**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "$(cat <<'EOF'
refactor(server-section): wrap body region in Button (option A)

Mirror the ForwardingRowView split: the body region (chevron,
monogram, name, count badge) is wrapped in a single
Button(action: handleRowTap) for keyboard focus and Enter/Space
handling, while refresh and ellipsis remain sibling Buttons
outside it. Avoids nested-Button hit-testing ambiguity.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: ServerSectionView 접근성 트리 완성

**목적:** 행 라벨 = `[primaryLabel] [secondaryLabel]`, value = "펼침/접힘", hint = "이중 탭하여 펼치기/접기/재스캔". refresh·ellipsis는 자식 노드로 유지.

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift` — Task 5 결과 sectionHeader의 modifier 묶음

- [ ] **Step 6.1: 본문 Button에 접근성 modifier 추가**

Task 5.2에서 작성한 `sectionHeader`의 본문 Button — `.buttonStyle(.plain)` 줄을 찾아 그 직후에 modifier를 부착:

```swift
        }
        .buttonStyle(.plain)

        // ↓ 추가 ↓
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(primaryLabel) \(secondaryLabel)")
        .accessibilityValue(isOffline ? "오프라인" : (section.isExpanded ? "펼침" : "접힘"))
        .accessibilityHint(isOffline
            ? "이중 탭하여 재스캔"
            : "이중 탭하여 \(section.isExpanded ? "접기" : "펼치기")")

        if case .scanning = section.scanState {  // ← 기존 형제 코드 그대로
```

변경 요점:
- modifier는 **본문 Button**에만 부착 — refresh/ellipsis는 자신의 라벨을 그대로 유지하므로 영향 없음
- `.contain`: 본문 안의 자식 ServerMonogram·count badge는 `.accessibilityHidden(true)` 또는 자체 label로 처리되므로 트리에 노이즈 안 남김
- `.accessibilityLabel`: 서버명 + 호스트:포트
- `.accessibilityValue`: 상태 토큰. 오프라인 / 펼침 / 접힘
- `.accessibilityHint`: 이중 탭 시 동작 안내

- [ ] **Step 6.2: 빌드 확인**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6.3: VoiceOver 수동 점검**

VoiceOver ⌘F5 ON:
- 펼쳐진 서버 행 → "[이름] [user@host:port], 펼침. 이중 탭하여 접기"
- 접힌 서버 행 → "[이름] [user@host:port], 접힘. 이중 탭하여 펼치기"
- 오프라인 서버 행 → "[이름] [user@host:port], 오프라인. 이중 탭하여 재스캔"
- chevron 노드는 들리지 **않음**
- 행 다음 노드 = refresh, 그 다음 = "더보기 메뉴"

- [ ] **Step 6.4: 커밋**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "$(cat <<'EOF'
feat(a11y): expose server row state via accessibilityValue/Hint

Add .accessibilityElement(.contain), label combining name and
ssh target, value reflecting expanded/collapsed/offline state,
and a state-specific hint. Refresh and ellipsis remain
independent Tab stops.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 통합 수동 검증 (스펙 §6 전체 체크리스트)

**목적:** 모든 변경이 합쳐진 상태에서 키보드·VoiceOver·시각·단축키 회귀를 확인.

**Files:** (코드 변경 없음 — 검증만)

- [ ] **Step 7.1: clean build**

Run: `xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug clean build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7.2: 키보드 전용 (VoiceOver OFF)**

Xcode ⌘R → 메뉴바 PortBridge 클릭. 다음을 모두 통과해야 한다:

- [ ] 첫 Tab → 검색창 또는 첫 서버 본문에 시각 포커스 링
- [ ] Tab 흐름: `서버 본문 → refresh → ⋯ → 포워딩 star → 포워딩 본문 → 브라우저(active) → 다음 포워딩 star …`
- [ ] 서버 본문 포커스 + Enter → 펼침/접힘 토글
- [ ] 오프라인 서버 본문 포커스 + Enter → 재스캔 트리거
- [ ] 포워딩 본문(active) 포커스 + Enter → 포워딩 끄기 (상태 dot 변화)
- [ ] 포워딩 본문(idle) 포커스 + Enter → 포워딩 켜기
- [ ] star Button 포커스 + Space/Enter → 즐겨찾기 토글 (icon star ↔ star.fill)
- [ ] 브라우저 버튼 포커스 + Space 또는 Enter → 기본 브라우저에서 `http://localhost:N` 열림
- [ ] Shift+Tab 역방향 흐름 정상

- [ ] **Step 7.3: VoiceOver (⌘F5)**

VoiceOver ON:

- [ ] 서버 본문 발화: "[이름] [user@host:port], 펼침/접힘/오프라인. 이중 탭하여 …"
- [ ] chevron이 별도 노드로 들리지 **않음**
- [ ] refresh 노드 = "[서버명] 포트 재스캔 버튼" (본문 다음)
- [ ] ellipsis 노드 = "[서버명] 더보기 메뉴" (refresh 다음)
- [ ] 포워딩 star 노드 = "즐겨찾기 추가 / 해제 버튼"
- [ ] 포워딩 본문 발화: "포트 N, [서버] · 포워딩 중/대기, 이중 탭하여 포워딩 끄기/켜기"
- [ ] Active 포워딩 본문 다음 노드 = "브라우저에서 열기 버튼"
- [ ] Idle/Starting 행은 브라우저 노드 **없음**, 본문 다음 곧바로 다음 행 star

VoiceOver OFF 복원.

- [ ] **Step 7.4: 시각 회귀**

- [ ] 호버 시 OpenInBrowserButton 배경 idle→hover 전환 그대로
- [ ] 호버 없이도 Active 행마다 브라우저 칩이 보임 (Task 2)
- [ ] chevron 펼침/접힘 시 회전(혹은 down/right 교체) 시각 유지
- [ ] 서버 행 마우스 클릭 → expand/collapse 정상
- [ ] 좁은 폭(480pt) → 브라우저 칩 잘림 없음
- [ ] Button + `.plain` 래핑으로 인한 의도치 않은 hover 배경 색상 변화 **없음** (스펙 §7 비결정 사항 1)

- [ ] **Step 7.5: 단축키·기존 기능 회귀**

- [ ] `⌘R` 전체 재스캔
- [ ] `⌘N` 새 서버 추가
- [ ] `⌘⇧E` (모두 펼치기/접기 단축키가 있다면) 정상
- [ ] 에러 토스트 5초 자동 소멸 + 수동 닫기 버튼
- [ ] 포트 충돌 시트 입력 검증 (Task 0의 2번) 정상

- [ ] **Step 7.6: 발견된 비결정 사항 후속 처리**

만약 다음 중 하나가 실제로 문제로 드러나면 별도 커밋으로 보완:

- 호버 시 Button + `.plain`이 의도치 않은 배경을 그림 → HStack의 `.background()`를 호버 상태로 분기
- Menu(ellipsis) 클릭이 부모 Button과 충돌 → Menu에 `.simultaneousGesture` 추가 또는 부모 Button의 `.allowsHitTesting` 조정
- 시각 포커스 링이 너무 약함 → `@FocusState` + `.overlay`로 명시 ring 추가

문제 없으면 Step 7.7로 진행.

- [ ] **Step 7.7: 검증 결과 기록 커밋 (선택)**

수동 검증 통과 사실을 코드 커밋이 아닌 PR description에 기록. 별도 커밋은 만들지 않음.

만약 Step 7.6에서 보완 커밋이 생겼다면 그 커밋만 git log에 남으면 됨.

---

## Task 8: PR 생성 결정 (사용자 확인)

**목적:** 워크트리에서 main으로 어떻게 통합할지 결정.

**Files:** (코드 변경 없음)

- [ ] **Step 8.1: 커밋 로그 확인**

Run: `git log --oneline origin/main..HEAD`
Expected (Task 7.6 보완 없을 경우):
```
xxxxxxx feat(a11y): expose server row state via accessibilityValue/Hint
xxxxxxx refactor(server-section): wrap row in Button for keyboard focus
xxxxxxx refactor(server-section): demote chevron to visual cue
xxxxxxx feat(a11y): expose OpenInBrowserButton as separate VO node
xxxxxxx fix(a11y): always show OpenInBrowserButton on active rows
xxxxxxx refactor(forwarding-row): wrap row in Button for keyboard focus
xxxxxxx fix(ui): validate local port in PortConflictSheet
xxxxxxx fix(a11y): meet WCAG 1.4.11 for input border in light mode
c5f293f docs(specs): row-internal secondary actions accessibility design
```

총 9개 커밋. 모두 한 PR로 묶어도 작은 단위로 분리되어 리뷰 가능.

- [ ] **Step 8.2: 사용자에게 PR 옵션 제시**

다음 중 사용자 의도 확인:
1. 단일 PR (제목 예: `a11y: WCAG sweep + row Tab navigation`)
2. 분리 PR — WCAG sweep(Task 0) + row a11y(Task 1–6)을 별도 PR

사용자가 단일 PR을 선호하면 Step 8.3으로, 분리를 선호하면 Task 0 커밋만 먼저 main으로 빠르게 보내고 나머지를 후속 PR로.

- [ ] **Step 8.3: 단일 PR 생성 (옵션)**

```bash
git push -u origin worktree-wcag-input-border
gh pr create --title "a11y: WCAG sweep + row Tab navigation" --body "$(cat <<'EOF'
## Summary
- WCAG 1.4.11 입력 외곽선 라이트 모드 통과 (2.21:1 → 3.26:1)
- PortConflictSheet 입력 검증 + Enter 무반응 버그 수정
- ForwardingRowView 행 전체 Tab focus + OpenInBrowserButton 항상 노출
- ServerSectionView chevron 격하 + 행 disclosure Button 통합

설계 문서: docs/superpowers/specs/2026-05-21-row-secondary-actions-design.md

## Test plan
- [x] xcodebuild Debug 빌드 통과
- [x] 키보드 전용 Tab 흐름 (계획서 Task 7.2)
- [x] VoiceOver ⌘F5 발화 검증 (Task 7.3)
- [x] 시각 회귀 (Task 7.4)
- [x] 단축키·기존 기능 회귀 (Task 7.5)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

### Spec coverage

스펙 섹션 → 태스크 매핑:

| 스펙 섹션 | 태스크 |
|---|---|
| §1 배경 | (설명) |
| §2 설계 원칙 | (전 태스크 가이드) |
| §3 ForwardingRow 시각 (호버 의존 제거) | Task 2 |
| §3 ForwardingRow 구조 (Button 래핑) | Task 1 |
| §3 ForwardingRow 접근성 (.contain) | Task 3 |
| §4 chevron 시각 단서 | Task 4 |
| §4 행 disclosure Button | Task 5 |
| §4 ServerSection 접근성 (.value/.hint) | Task 6 |
| §5 Tab 흐름 | Task 7.2 검증 |
| §6 검증 시나리오 | Task 7 전체 |
| §7 비결정 사항 (호버 색상) | Task 7.4, 7.6 |
| §7 비결정 사항 (Menu 충돌) | Task 5.4, 7.6 |
| §7 비결정 사항 (FocusState) | Task 5.5, 7.6 |
| §8 영향 범위 | (Files 섹션) |

선행 항목 1·2번도 Task 0으로 흡수 — 모든 스펙·리뷰 요구사항이 태스크에 매핑됨.

### Placeholder scan

- "TBD"/"TODO" 없음
- "appropriate error handling"·"add validation" 같은 모호 표현 없음
- 모든 코드 변경 step에 실제 교체 코드 명시
- 빌드 명령·검증 명령에 정확한 expected output 명시

### Type consistency

- `accessibilityLabel` (private computed property, ForwardingRowView:127) — Task 3에서 동일 식별자로 참조
- `handleRowTap()` — Task 5에서 동일 이름 유지 (스펙·실제 코드와 일치)
- `primaryLabel`·`secondaryLabel` — Task 5·6에서 일관 사용
- `section.isExpanded` 프로퍼티 — 전체 태스크에서 동일하게 참조

issues 없음.

---

**계획 완료.** 저장 경로: `docs/superpowers/plans/2026-05-21-row-secondary-actions.md`
