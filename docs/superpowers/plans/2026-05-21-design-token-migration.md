# Design Token Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec(`docs/superpowers/specs/2026-05-21-design-token-migration-design.md`)에 정의된 정확 일치 정책에 따라 35건의 매직 넘버(`4/8/12/16`, `cornerRadius: 6`)를 `PBLayout.Space.s1..s4` 및 `PBLayout.Radius.sm` 참조로 교체한다. 픽셀 동등 보장, outlier(`padding: 6` 6건, `cornerRadius: 4/5` 3건, `spacing: 1/10/24` 등)는 손대지 않는다.

**Architecture:** 파일별로 1개 Task. 같은 리터럴이 한 파일 내 다수 등장하면 `Edit(replace_all=true)`로 일괄 변경, 단일 등장은 `replace_all=false`로 unique context와 함께 변경. 각 Task 끝에 `xcodebuild build`로 컴파일 회귀를 즉시 검출. 마지막 Task에서 lint/format/단일 커밋.

**Tech Stack:** Swift, SwiftUI, AppKit, xcodebuild, SwiftLint, SwiftFormat.

**Working directory:** `/Users/youngho.jeon/datamaker/PortBridge/.claude/worktrees/design-tokens-extract` (git worktree, branch `worktree-design-tokens-extract`). 모든 경로는 이 디렉토리 기준.

**Build command (every task):**
```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

---

## Task 1: `PortBridge/ContentView.swift` (5건)

**Files:**
- Modify: `PortBridge/ContentView.swift`

**Targets:** L33 (spacing 4 → s1), L40 (padding 4 → s1), L68/L72 (cornerRadius 6 → sm, 2건), L113 (spacing 12 → s3)

- [ ] **Step 1.1: errorStack VStack spacing**

Edit `PortBridge/ContentView.swift` with `replace_all=false`:
- old_string:
  ```
  if !vm.errors.isEmpty {
              VStack(spacing: 4) {
  ```
- new_string:
  ```
  if !vm.errors.isEmpty {
              VStack(spacing: PBLayout.Space.s1) {
  ```

- [ ] **Step 1.2: errorStack bottom padding**

Edit `PortBridge/ContentView.swift` with `replace_all=false`:
- old_string:
  ```
          .padding(.horizontal)
          .padding(.bottom, 4)
  ```
- new_string:
  ```
          .padding(.horizontal)
          .padding(.bottom, PBLayout.Space.s1)
  ```

- [ ] **Step 1.3: errorToast RoundedRectangle cornerRadius (2건 동시)**

Edit `PortBridge/ContentView.swift` with `replace_all=true` — 이 파일에는 `cornerRadius: 6` 두 곳뿐이며 모두 errorToast 같은 의도:
- old_string: `RoundedRectangle(cornerRadius: 6, style: .continuous)`
- new_string: `RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)`

- [ ] **Step 1.4: PortConflictSheet VStack spacing**

Edit `PortBridge/ContentView.swift` with `replace_all=false`:
- old_string: `VStack(alignment: .leading, spacing: 12) {`
- new_string: `VStack(alignment: .leading, spacing: PBLayout.Space.s3) {`

- [ ] **Step 1.5: Build verification**

Run:
```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. 실패 시 직전 Edit 되돌리고 unique context 재확인.

---

## Task 2: `PortBridge/Views/ServerSectionView.swift` (15건)

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift`

**Targets:**
- `.padding(.vertical, 4)` × 5건 (L60, L67, L73, L97, L341)
- `HStack(spacing: 8) {` × 5건 (L63, L120, L122, L320, L388)
- `VStack(alignment: .leading, spacing: 8) {` × 2건 (L316, L363)
- `VStack(alignment: .leading, spacing: 4) {` × 1건 (L372)
- `RoundedRectangle(cornerRadius: 6, style: .continuous)` × 2건 (L258, L260)

(spacing 1 at L138, padding 6 at L157/L197/L378/L396, padding 1 at L158, padding 2 at L396은 outlier로 손대지 않음.)

- [ ] **Step 2.1: `.padding(.vertical, 4)` 일괄 swap (5건)**

Edit with `replace_all=true`:
- old_string: `.padding(.vertical, 4)`
- new_string: `.padding(.vertical, PBLayout.Space.s1)`

이 패턴은 정확 매칭이라 다른 형태(예: `.padding(.horizontal, 4)`, `spacing: 4`, `frame(width: 4)`)는 영향받지 않는다.

- [ ] **Step 2.2: `HStack(spacing: 8) {` 일괄 swap (5건)**

Edit with `replace_all=true`:
- old_string: `HStack(spacing: 8) {`
- new_string: `HStack(spacing: PBLayout.Space.s2) {`

- [ ] **Step 2.3: `VStack(alignment: .leading, spacing: 8) {` 일괄 swap (2건)**

Edit with `replace_all=true`:
- old_string: `VStack(alignment: .leading, spacing: 8) {`
- new_string: `VStack(alignment: .leading, spacing: PBLayout.Space.s2) {`

- [ ] **Step 2.4: ToolInstallGuide inner VStack spacing 4 → s1**

Edit with `replace_all=false`:
- old_string: `VStack(alignment: .leading, spacing: 4) {`
- new_string: `VStack(alignment: .leading, spacing: PBLayout.Space.s1) {`

(이 파일 내 `VStack(alignment: .leading, spacing: 1) {`는 outlier로 보존됨 — 매칭 패턴이 정확히 일치할 때만 swap.)

- [ ] **Step 2.5: ServerMonogram cornerRadius 6 일괄 swap (2건)**

Edit with `replace_all=true`:
- old_string: `RoundedRectangle(cornerRadius: 6, style: .continuous)`
- new_string: `RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)`

(이 파일 내 다른 `cornerRadius: 6` 없음. `cornerRadius: 4`는 L397에 있으나 outlier로 보존.)

- [ ] **Step 2.6: Build verification**

```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2.7: Sanity-check outliers untouched**

```bash
grep -nE "spacing: 1\b|cornerRadius: 4\b|padding\(\.(horizontal|vertical), 6\b|padding\(\.(horizontal|vertical), 1\b|padding\(\.(horizontal|vertical), 2\b" PortBridge/Views/ServerSectionView.swift
```
Expected: outlier 라인들(L138, L157, L158, L197, L378, L396, L397)이 여전히 리터럴 유지. 누락 시 직전 step 중 하나가 잘못된 replace_all을 수행했음 — git diff로 검증 후 되돌리기.

---

## Task 3: `PortBridge/Views/ServerListView.swift` (7건)

**Files:**
- Modify: `PortBridge/Views/ServerListView.swift`

**Targets:** L82·L102 (spacing 12 → s3, 2건), L204 (padding 16 → s4), L210 (spacing 8 → s2), L224 (padding 4 → s1), L276 (padding 12 → s3), L277 (padding 8 → s2)

(L155 padding 2, L205 padding 6, L223 padding 7, L117 padding 24, L226/L230 cornerRadius 5는 outlier — 손대지 않음.)

- [ ] **Step 3.1: emptyState/noSearchResults `VStack(spacing: 12)` 일괄 swap (2건)**

Edit with `replace_all=true`:
- old_string: `VStack(spacing: 12) {`
- new_string: `VStack(spacing: PBLayout.Space.s3) {`

- [ ] **Step 3.2: allServersHeader horizontal padding**

Edit with `replace_all=false`:
- old_string:
  ```
      .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(.bar)
      }

      private var serverListHeader: some View {
  ```
- new_string:
  ```
      .padding(.horizontal, PBLayout.Space.s4)
          .padding(.vertical, 6)
          .background(.bar)
      }

      private var serverListHeader: some View {
  ```

(`.padding(.vertical, 6)`는 outlier로 보존.)

- [ ] **Step 3.3: serverListHeader HStack spacing**

Edit with `replace_all=false`:
- old_string: `HStack(spacing: 8) {`
- new_string: `HStack(spacing: PBLayout.Space.s2) {`

- [ ] **Step 3.4: TextField vertical padding 4**

Edit with `replace_all=false`:
- old_string:
  ```
                  .padding(.horizontal, 7)
                  .padding(.vertical, 4)
  ```
- new_string:
  ```
                  .padding(.horizontal, 7)
                  .padding(.vertical, PBLayout.Space.s1)
  ```

(`.padding(.horizontal, 7)`은 outlier로 보존.)

- [ ] **Step 3.5: serverListHeader horizontal padding 12**

Edit with `replace_all=false`:
- old_string:
  ```
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)
      }
  }
  ```
- new_string:
  ```
      .padding(.horizontal, PBLayout.Space.s3)
      .padding(.vertical, PBLayout.Space.s2)
      .background(.bar)
      }
  }
  ```

(Step 3.5는 두 padding을 한 번에 처리한다 — 같은 method chain의 인접한 두 줄이라 단일 Edit이 자연스럽다.)

- [ ] **Step 3.6: Build verification**

```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3.7: Sanity-check outliers untouched**

```bash
grep -nE "cornerRadius: 5\b|padding\(\.(horizontal|vertical), (2|6|7|24)\b" PortBridge/Views/ServerListView.swift
```
Expected: L117, L155, L205, L223, L226, L230 outlier 유지.

---

## Task 4: `PortBridge/Views/ForwardingRowView.swift` (7건)

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift`

**Targets:** L121·L186 (padding 4 → s1, 2건), L178 (spacing 4 → s1), L185 (padding 8 → s2), L188·L192·L195 (cornerRadius 6 → sm, 3건; L195는 `contentShape(...)` 안에 있음)

- [ ] **Step 4.1: `.padding(.vertical, 4)` 일괄 swap (2건)**

Edit with `replace_all=true`:
- old_string: `.padding(.vertical, 4)`
- new_string: `.padding(.vertical, PBLayout.Space.s1)`

- [ ] **Step 4.2: OpenInBrowserButton HStack spacing 4**

Edit with `replace_all=false`:
- old_string: `HStack(spacing: 4) {`
- new_string: `HStack(spacing: PBLayout.Space.s1) {`

- [ ] **Step 4.3: OpenInBrowserButton horizontal padding 8**

Edit with `replace_all=false`:
- old_string: `.padding(.horizontal, 8)`
- new_string: `.padding(.horizontal, PBLayout.Space.s2)`

- [ ] **Step 4.4: `RoundedRectangle(cornerRadius: 6, style: .continuous)` 일괄 swap (3건)**

Edit with `replace_all=true`:
- old_string: `RoundedRectangle(cornerRadius: 6, style: .continuous)`
- new_string: `RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)`

(L188 `.background(...)`의 fill, L192 `.overlay(...)`의 strokeBorder, L195 `.contentShape(...)`의 shape — 세 곳 모두 동일 의도. 이 파일에 다른 `cornerRadius:` 없음.)

- [ ] **Step 4.5: Build verification**

```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

---

## Task 5: `PortBridge/Views/AddServerSheet.swift` (1건)

**Files:**
- Modify: `PortBridge/Views/AddServerSheet.swift`

**Target:** L67 (spacing 16 → s4)

- [ ] **Step 5.1: body VStack spacing 16**

Edit with `replace_all=false`:
- old_string: `VStack(alignment: .leading, spacing: 16) {`
- new_string: `VStack(alignment: .leading, spacing: PBLayout.Space.s4) {`

- [ ] **Step 5.2: Build verification**

```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

---

## Task 6: Final verification, lint/format, commit

**Files:** N/A (verification only, then commit)

- [ ] **Step 6.1: Aggregate diff inspection**

```bash
git diff --stat PortBridge/
```
Expected: 5개 파일(`ContentView.swift`, `Views/ServerSectionView.swift`, `Views/ServerListView.swift`, `Views/ForwardingRowView.swift`, `Views/AddServerSheet.swift`) 변경. 합계 약 35줄 수정. `MenuBarIconView.swift`, `ActiveSectionHeader.swift`, `AllServersSectionHeader.swift`는 미변경.

- [ ] **Step 6.2: Full token-reference count**

```bash
grep -rE "PBLayout\.(Space|Radius)" PortBridge/ContentView.swift PortBridge/Views/ServerSectionView.swift PortBridge/Views/ServerListView.swift PortBridge/Views/ForwardingRowView.swift PortBridge/Views/AddServerSheet.swift | wc -l
```
Expected: 정확히 `35`. 다르면 어느 Task에서 누락/중복 발생했는지 `git diff`로 추적.

- [ ] **Step 6.3: SwiftFormat lint**

```bash
swiftformat --lint PortBridge/ 2>&1 | tail -5
```
Expected: `0 file(s) updated` 또는 동등한 무변경 메시지. 변경 제안이 나오면 spec의 §6 mitigation에 따라 토큰 표현을 유지하는 방향으로 조정 후 재실행.

- [ ] **Step 6.4: SwiftLint**

```bash
swiftlint lint --quiet PortBridge/ 2>&1 | tail -10
```
Expected: 신규 위반 0건. 기존 위반은 그대로일 수 있음(이번 작업 범위 외).

- [ ] **Step 6.5: Final clean build**

```bash
xcodebuild -scheme PortBridge -destination 'platform=macOS' clean build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. 캐시된 incremental build가 가려둔 회귀가 있는지 클린 빌드로 마지막 검증.

- [ ] **Step 6.6: Single commit**

```bash
git add PortBridge/ContentView.swift \
        PortBridge/Views/ServerSectionView.swift \
        PortBridge/Views/ServerListView.swift \
        PortBridge/Views/ForwardingRowView.swift \
        PortBridge/Views/AddServerSheet.swift
```

Then commit (HEREDOC to preserve formatting):
```bash
git commit -m "$(cat <<'EOF'
refactor(views): swap exact-match magic numbers to PBLayout tokens

- 4/8/12/16 (spacing, padding) → PBLayout.Space.s1..s4
- cornerRadius 6 → PBLayout.Radius.sm
- outlier values (padding 6, cornerRadius 4/5, spacing 1/10/24 등) 보존

Spec: docs/superpowers/specs/2026-05-21-design-token-migration-design.md
Plan: docs/superpowers/plans/2026-05-21-design-token-migration.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Then verify:
```bash
git status
```
Expected: 5개 변경 파일이 `commit`에 포함되어 working tree에서 사라짐. 다음 파일들은 이 커밋에 **포함하지 않는다** — 이번 worktree에서 이미 변경되었지만 별도 의도(토큰 정의 추가/문서 broaden, spec/plan 문서)이므로 사용자가 커밋 boundary를 따로 결정한다:
- `PortBridge/Views/Layout.swift` (신규)
- `PortBridge/Views/DesignTokens.swift` (확장)
- `docs/superpowers/specs/2026-05-21-design-token-migration-design.md` (신규)
- `docs/superpowers/plans/2026-05-21-design-token-migration.md` (신규)

위 4개 파일이 `git status`에 untracked/modified로 남아있으면 정상이다. 사용자가 별도 커밋/PR 전략을 지시할 때까지 stage하지 않는다.

- [ ] **Step 6.7: Notify user — manual UI verification required**

CLI 테스트 러너는 LaunchServices 환경 이슈로 실패함이 알려져 있으므로 자동 UI 검증 불가. 사용자에게 다음을 요청:

> Xcode에서 PortBridge scheme을 ⌘R로 실행해 다음 영역의 외관이 마이그레이션 전과 동일한지 1회 확인 부탁드립니다:
> - 메뉴바 팝오버 헤더 (검색바, allServersHeader)
> - 서버 섹션 헤더 (chevron · monogram · 카운트 배지)
> - 활성 포워딩 row (즐겨찾기 별, 상태 아이콘, "브라우저에서 열기" 버튼)
> - 오류 토스트 (forced trigger 어려우면 스크린샷만)
> - 서버 추가/편집 시트
>
> 픽셀 차이 보고 시 어느 영역인지 알려주시면 해당 Task의 step을 되짚어 검증합니다.

---

## Notes for the implementer

1. **Order matters within a Task, not across Tasks.** Task 1–5는 서로 독립적이라 병렬 실행 가능. 다만 한 파일 내 step은 위→아래 순서를 지킬 것 — 같은 줄을 두 번 손대지 않도록 plan이 짜여 있다.

2. **`replace_all=true`는 의도 검증 필수.** plan에 명시된 replace_all step은 모두 사전 grep으로 "이 패턴이 정확히 N건이고 모두 같은 의도임"을 확인했다. 실행 중 grep 결과가 plan과 다르면 (예: 기대 N=5인데 6건 발견) 즉시 멈추고 차이를 보고할 것 — 신규 매직 넘버가 추가되었을 수 있다.

3. **Outlier는 절대 손대지 않는다.** 정책의 핵심. plan의 sanity-check step(2.7, 3.7)을 건너뛰지 말 것.

4. **빌드 실패 시 절차:**
   - 직전 Edit의 `git diff` 확인
   - old_string이 unique 매치 실패한 경우 surrounding context 확장 후 재시도
   - new_string에 오타 (`PBLayout.Space.s1` 등) 확인
   - 절대 `--no-verify`로 우회하지 말 것
