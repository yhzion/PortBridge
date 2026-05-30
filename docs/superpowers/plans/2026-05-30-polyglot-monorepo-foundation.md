# 폴리글랏 모노레포 기반(#1) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **참고:** 본 계획서는 설계 스펙 §5.8의 "임시(ephemeral) 작업 스펙"에 해당한다. 최종 PR 머지에는 포함하지 않으며(`docs/superpowers/plans/`는 worktree 작업용), 헌법 문서(`docs/superpowers/specs/2026-05-30-polyglot-monorepo-foundation-design.md`)만 영구 보존한다.

**Goal:** PortBridge 레포를 무중단으로 폴리글랏 모노레포(Swift macOS 앱 = `apps/macos/`, Rust core/CLI = `crates/`)로 재구성하고, 병렬 에이전트 조율 규약(`AGENTS.md`)을 확립한다.

**Architecture:** 위험한 이동을 먼저(Step), 순수 추가인 Rust를 나중에. 각 변경 후 Swift 빌드+유닛테스트 green을 검증 게이트로 둔다. Swift 프로젝트는 소스 폴더와 `.xcodeproj`를 함께 옮겨 `SOURCE_ROOT` 상대 참조를 보존하므로 프로젝트 내부는 안 깨진다. lint 설정은 루트 유지(githook/lint.yml 무수정).

**Tech Stack:** Xcode 26.5(`xcodebuild`), Cargo 1.92(Rust workspace), GitHub Issues/`gh` CLI, swiftformat/swiftlint/periphery.

**전제:** 현재 worktree `polyglot-monorepo-foundation`(브랜치 `worktree-polyglot-monorepo-foundation`)에서 작업한다. 설계 스펙은 이미 커밋됨(`d58623d`).

---

## 파일 구조 (생성/수정 맵)

| 동작 | 경로 | 책임 |
|------|------|------|
| 이동 | `PortBridge/` → `apps/macos/PortBridge/` | Swift 소스 |
| 이동 | `PortBridge.xcodeproj/` → `apps/macos/PortBridge.xcodeproj/` | Xcode 프로젝트 |
| 이동 | `PortBridgeTests/` → `apps/macos/PortBridgeTests/` | 유닛 테스트 |
| 이동 | `PortBridgeUITests/` → `apps/macos/PortBridgeUITests/` | UI 테스트 |
| 이동 | `install.sh` → `apps/macos/install.sh` | 소스 빌드·설치(자기위치 기준) |
| 수정 | `.periphery.yml` | `project` 경로 1줄 |
| 수정 | `.github/workflows/release.yml` | `working-directory` + 아티팩트 경로 |
| 수정 | `.gitignore` | Rust `target/` 추가 |
| 생성 | `Cargo.toml` | workspace 루트 |
| 생성 | `rustfmt.toml` | Rust 포맷 설정 |
| 생성 | `crates/portbridge-core/{Cargo.toml,src/lib.rs}` | 코어 라이브러리 골격 |
| 생성 | `crates/portbridge-cli/{Cargo.toml,src/main.rs}` | CLI 바이너리 골격 |
| 생성 | `.github/workflows/rust.yml` | Rust CI |
| 생성 | `AGENTS.md` | 조율 표준 규약(SSOT) |
| 생성 | `CLAUDE.md` | AGENTS.md 포인터 |
| 무수정 | `install-release.sh`, `.swiftlint.yml`, `.swiftformat`, `.github/workflows/lint.yml`, githooks | 변경 불필요(근거: 스펙 §2.1) |

---

## Task 1: 베이스라인 캡처 (이동 전 green 확인)

이동 전 현재 레이아웃에서 Swift 빌드+유닛테스트가 green임을 기록한다. 이후 단계의 비교 기준이다.

**Files:** 없음 (검증 전용, 커밋 없음)

- [ ] **Step 1: 현재 레이아웃에서 빌드**

Run:
```bash
cd /Users/youngho.jeon/yhzion/PortBridge/.claude/worktrees/polyglot-monorepo-foundation
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -5
```
Expected: 마지막 줄에 `** BUILD SUCCEEDED **`

- [ ] **Step 2: 현재 레이아웃에서 유닛 테스트**

Run:
```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge \
  -destination 'platform=macOS' -only-testing:PortBridgeTests 2>&1 | tail -8
```
Expected: `** TEST SUCCEEDED **` (PortBridgeTests 전 케이스 통과)

> 만약 `-only-testing:PortBridgeTests`가 스킴 설정 문제로 실패하면 `-skip-testing:PortBridgeUITests`로 대체한다. 이 명령(성공한 형태)을 이후 모든 Swift 검증 게이트에서 동일하게 사용한다.

- [ ] **Step 3: 베이스라인 기록**

두 명령의 결과(SUCCEEDED 여부, 테스트 수)를 작업 메모에 적는다. 이것이 "무중단" 비교 기준이다.

---

## Task 2: Swift를 `apps/macos/`로 이동 + 경로의존 파일 수정

**Files:**
- 이동: `PortBridge/`, `PortBridge.xcodeproj/`, `PortBridgeTests/`, `PortBridgeUITests/`, `install.sh` → `apps/macos/`
- 수정: `.periphery.yml`
- 수정: `.github/workflows/release.yml`

- [ ] **Step 1: `apps/macos/` 생성 후 git mv**

Run:
```bash
mkdir -p apps/macos
git mv PortBridge apps/macos/PortBridge
git mv PortBridge.xcodeproj apps/macos/PortBridge.xcodeproj
git mv PortBridgeTests apps/macos/PortBridgeTests
git mv PortBridgeUITests apps/macos/PortBridgeUITests
git mv install.sh apps/macos/install.sh
```
Expected: 에러 없음. `git status`에 renamed 항목들이 보임.

- [ ] **Step 2: `.periphery.yml`의 project 경로 수정**

`.periphery.yml` 4번째 줄을 수정:

```yaml
project: apps/macos/PortBridge.xcodeproj
```
(기존 `project: PortBridge.xcodeproj` 에서 변경)

- [ ] **Step 3: `release.yml`에 working-directory 추가**

`.github/workflows/release.yml`에서 `build:` 잡 정의에 `defaults`를 추가한다. 기존:

```yaml
  build:
    name: Build ad-hoc signed macOS app
    runs-on: macos-latest

    steps:
```
다음으로 변경:

```yaml
  build:
    name: Build ad-hoc signed macOS app
    runs-on: macos-latest
    defaults:
      run:
        working-directory: apps/macos

    steps:
```

- [ ] **Step 4: `release.yml`의 upload-artifact 경로 수정**

같은 파일에서 `Upload workflow artifact` 스텝의 path를 수정한다. `uses:` 스텝은 `working-directory`를 따르지 않으므로 리포 루트 기준 경로가 필요하다. 기존:

```yaml
          path: |
            dist/PortBridge.zip
            dist/PortBridge.zip.sha256
```
다음으로 변경:

```yaml
          path: |
            apps/macos/dist/PortBridge.zip
            apps/macos/dist/PortBridge.zip.sha256
```

> `Build Release app` / `Ad-hoc sign and package` / `Upload GitHub Release assets` 스텝은 모두 `run:`이라 `defaults.run.working-directory: apps/macos`를 따르므로 내부의 상대경로(`build/Release/...`, `dist/...`)는 수정 불필요하다.

- [ ] **Step 5: 이동 후 Swift 빌드 검증**

Run:
```bash
xcodebuild -project apps/macos/PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 이동 후 유닛 테스트 검증**

Run:
```bash
xcodebuild test -project apps/macos/PortBridge.xcodeproj -scheme PortBridge \
  -destination 'platform=macOS' -only-testing:PortBridgeTests 2>&1 | tail -8
```
Expected: `** TEST SUCCEEDED **` (Task 1과 동일한 테스트 수)

- [ ] **Step 7: lint이 루트에서 여전히 동작하는지 검증**

Run:
```bash
swiftformat --lint . 2>&1 | tail -3
swiftlint --quiet 2>&1 | tail -5
```
Expected: swiftformat 위반 없음(종료코드 0), swiftlint error 없음. (`.swiftlint.yml`/`.swiftformat`는 루트 유지, `included:` 없어 cwd 스캔 → `apps/macos`의 `.swift`를 잡음.)

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "refactor(layout): move macOS app into apps/macos/

Relocate Swift sources, Xcode project, tests, and install.sh under
apps/macos/. Update .periphery.yml project path and release.yml
working-directory. Build + unit tests verified green post-move.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Cargo workspace + Rust 골격 추가

순수 additive 변경 — Swift를 건드리지 않는다.

**Files:**
- 생성: `Cargo.toml`, `rustfmt.toml`
- 생성: `crates/portbridge-core/Cargo.toml`, `crates/portbridge-core/src/lib.rs`
- 생성: `crates/portbridge-cli/Cargo.toml`, `crates/portbridge-cli/src/main.rs`
- 수정: `.gitignore`

- [ ] **Step 1: workspace 루트 `Cargo.toml` 생성**

Create `Cargo.toml`:
```toml
[workspace]
resolver = "2"
members = [
    "crates/portbridge-core",
    "crates/portbridge-cli",
]

[workspace.package]
edition = "2021"
license = "MIT"
repository = "https://github.com/yhzion/PortBridge"
```

- [ ] **Step 2: `rustfmt.toml` 생성**

Create `rustfmt.toml`:
```toml
edition = "2021"
max_width = 100
```

- [ ] **Step 3: core 크레이트 생성**

Create `crates/portbridge-core/Cargo.toml`:
```toml
[package]
name = "portbridge-core"
version = "0.0.0"
edition.workspace = true
license.workspace = true
repository.workspace = true

[dependencies]
```

Create `crates/portbridge-core/src/lib.rs`:
```rust
//! PortBridge 공유 코어 — SSH config 파싱, 포트 스캔, 터널 생명주기 로직의
//! 플랫폼 독립 단일 진실 공급원. 현재는 골격만 존재한다.
//! 실제 로직은 후속 이슈(#2)에서 추가한다.

/// 코어 크레이트의 패키지 버전을 반환하는 임시 골격 함수.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_reported() {
        assert_eq!(version(), "0.0.0");
    }
}
```

- [ ] **Step 4: cli 크레이트 생성**

Create `crates/portbridge-cli/Cargo.toml`:
```toml
[package]
name = "portbridge-cli"
version = "0.0.0"
edition.workspace = true
license.workspace = true
repository.workspace = true

[[bin]]
name = "portbridge"
path = "src/main.rs"

[dependencies]
portbridge-core = { path = "../portbridge-core" }
```

Create `crates/portbridge-cli/src/main.rs`:
```rust
//! PortBridge CLI — portbridge-core 위에 구축되는 크로스 플랫폼 진입점.
//! 현재는 골격만 존재한다. 실제 서브커맨드는 후속 이슈(#3)에서 추가한다.

fn main() {
    println!("PortBridge CLI (core {})", portbridge_core::version());
}
```

- [ ] **Step 5: `.gitignore`에 Rust `target/` 추가**

`.gitignore` 끝에 한 줄 추가:
```
target/
```

- [ ] **Step 6: Rust 빌드 검증**

Run:
```bash
cargo build --workspace 2>&1 | tail -5
```
Expected: `Finished` 라인 출력, 에러 없음.

- [ ] **Step 7: Rust 테스트 검증**

Run:
```bash
cargo test --workspace 2>&1 | tail -10
```
Expected: `test result: ok. 1 passed` (core의 `version_is_reported`).

- [ ] **Step 8: Rust 포맷 검증**

Run:
```bash
cargo fmt --all -- --check 2>&1 | tail -3
```
Expected: 출력 없음(종료코드 0).

- [ ] **Step 9: Swift 무중단 재확인 (additive 검증)**

Run:
```bash
xcodebuild -project apps/macos/PortBridge.xcodeproj -scheme PortBridge -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` (Rust 추가가 Swift에 영향 없음 확인).

- [ ] **Step 10: 커밋**

```bash
git add -A
git commit -m "feat(rust): add Cargo workspace with core/cli skeletons

Introduce crates/portbridge-core (lib) and crates/portbridge-cli (bin)
as a compilable hello-world workspace. Pure additive change; Swift build
re-verified green. Logic porting deferred to follow-up issues.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `AGENTS.md` + `CLAUDE.md` 포인터 추가

**Files:**
- 생성: `AGENTS.md`
- 생성: `CLAUDE.md`

- [ ] **Step 1: `AGENTS.md` 생성**

Create `AGENTS.md`:
```markdown
# AGENTS.md — PortBridge 코딩 에이전트 작업 규약

이 문서는 PortBridge 레포에서 작업하는 **모든 코딩 에이전트**(Claude Code, codex,
opencode, pi 등)가 따르는 표준 규약이다. 세션 시작 시 읽고 따른다. 규칙의 단일
출처(SSOT)는 이 파일이며, `CLAUDE.md` 등 도구별 진입점은 이 파일을 가리키는
포인터일 뿐이다.

## 1. 레포 구조

- `apps/macos/` — macOS 메뉴바 앱 (Swift/SwiftUI/AppKit, Xcode 프로젝트)
- `crates/portbridge-core/` — 플랫폼 독립 코어 로직 (Rust 라이브러리)
- `crates/portbridge-cli/` — 크로스 플랫폼 CLI (Rust 바이너리)
- `docs/` — 영구 문서 (아키텍처, 본 규약, 설계 스펙)
- `.github/` — CI 워크플로

## 2. Ownership Zones

각 작업(이슈)은 정확히 하나의 zone만 수정한다.

| zone 라벨 | 수정 가능 경로 |
|-----------|----------------|
| `zone:core`  | `crates/portbridge-core/` |
| `zone:cli`   | `crates/portbridge-cli/` |
| `zone:tauri` | `crates/portbridge-tauri/` (향후) |
| `zone:macos` | `apps/macos/` |
| `zone:ci`    | `.github/` |
| `zone:docs`  | `docs/`, `README.md` |

### serial-only 공유 파일
다음 파일은 둘 이상의 이슈가 동시에 수정하면 충돌한다. 이를 수정하는 작업은 그
파일을 단독 소유하는 전용 직렬 이슈에서만 처리한다.
- 루트 `Cargo.toml` (workspace members)
- `.github/` 워크플로
- `README.md`, lint 설정(`.swiftlint.yml`, `.swiftformat`, `.periphery.yml`, `rustfmt.toml`)
- `AGENTS.md`, `CLAUDE.md`

## 3. 라벨 상태기계

- `status:ready` — 막힌 의존성 없음, 지금 픽업 가능
- `status:in-progress` — 점유됨 (assignee 존재)
- `status:blocked` — open인 blocked-by 있음
- `status:review` — PR open
- `zone:*` — §2의 구역
- `grade:1|2|3` — §5의 난이도

## 4. 픽업 가능 5조건

이슈가 병렬 픽업 가능(`status:ready`)하려면 모두 만족:
1. 단일 zone만 수정
2. serial-only 공유 파일 미수정
3. blocked-by가 전부 closed
4. 그 zone만으로 build + test green (독립 검증 가능)
5. 격리된 worktree/브랜치에서 작업, PR로만 머지

## 5. 난이도 grade

이슈의 내재적 속성(난이도 + blast radius). **모델 매핑은 이 repo에 없다** —
디스패치 시 사람이 결정한다.

| grade | 의미 | 예시 |
|-------|------|------|
| `grade:1` | 기계적, 단일 파일, 설계 결정 없음 | 필드 추가, 경로 수정, 순수함수 테스트 |
| `grade:2` | 정의된 인터페이스 위 구현, 중간 로직 | core API 위 CLI 서브커맨드 |
| `grade:3` | 비자명 로직 or 인터페이스·경계 정의(high blast radius) | core 타입/트레잇 설계, 파서 |

## 6. 픽업 절차 (레이스 안전)

1. 조회:
   ```bash
   gh issue list --label status:ready --search "no:assignee" \
     --json number,title,labels
   ```
   결과에서 `grade:N`이 지시받은 등급 이하인 이슈를 클라이언트 측에서 고른다.
   (GitHub 라벨은 OR 쿼리가 약하므로 grade 필터는 클라이언트에서 수행한다.)
2. 원자적 점유:
   ```bash
   gh issue edit <N> --add-assignee @me \
     --remove-label status:ready --add-label status:in-progress
   gh issue comment <N> --body "claimed by <agent-id> at <ISO-8601 timestamp>"
   ```
3. 재조회로 레이스 확인: 같은 창에 다른 에이전트가 점유했으면(assignee 둘 / 더 이른
   claim 댓글), 늦은 쪽이 양보하고 다른 이슈로 이동한다.

## 7. 중복 구현 방지

1. 점유-우선(§6) — 이미 점유된 이슈는 시작하지 않는다.
2. 1이슈-1zone, 1이슈-1PR — 한 zone은 동시에 한 open 이슈만 소유.
3. 인터페이스 우선 — 캐노니컬 구현을 한 번 정의하고 `use portbridge_core::...`로
   의존. 재정의 금지.
4. 브랜치/워크트리 = 이슈 키 — 브랜치 `issue-<N>-<slug>`. 착수 전 동일 브랜치/PR이
   #N을 참조하는지 확인.
5. 착수 전 pre-flight 검색 — 만들려는 심볼/기능이 코드 또는 open PR에 이미 있는지
   검색. 없을 때만 작성.

## 8. readiness 갱신 (수동)

이슈를 close(또는 PR 머지)할 때, 그 이슈를 blocked-by로 가진 이슈들을 확인해
의존성이 모두 닫혔으면 `status:blocked → status:ready`로 전환한다.
```bash
gh issue edit <dependent-N> --remove-label status:blocked --add-label status:ready
```

## 9. 작업 단위 규약

- 브랜치: `issue-<N>-<slug>`
- 이슈당 worktree 1개. PR로만 머지하며, 머지 전 그 zone의 build+test가 green이어야 한다.
- 검증 게이트:
  - Swift(`zone:macos`): `xcodebuild -project apps/macos/PortBridge.xcodeproj -scheme PortBridge build`
    + `xcodebuild test -project apps/macos/PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests`
  - Rust(`zone:core`/`zone:cli`): `cargo build --workspace` + `cargo test --workspace`

## 10. 문서 수명

- **영구(repo)**: 아키텍처, 본 규약, 설계 스펙(`docs/superpowers/specs/`). 불변식만.
- **임시(트리 밖)**: 특정 기능의 구현 계획은 GitHub 서브이슈 본문 또는 worktree
  로컬 gitignore 파일에 둔다. 머지/close 시 사라져 트리에 noise를 남기지 않는다.
```

- [ ] **Step 2: `CLAUDE.md` 포인터 생성**

Create `CLAUDE.md`:
```markdown
# CLAUDE.md

이 레포의 코딩 에이전트 작업 규약·조율 규칙의 단일 출처는 **[AGENTS.md](AGENTS.md)**다.
세션 시작 시 AGENTS.md를 읽고 따른다.

이 파일은 Claude Code를 AGENTS.md로 안내하기 위한 포인터일 뿐이며, 규칙을 여기에
중복 기재하지 않는다.
```

- [ ] **Step 3: 커밋**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "docs(agents): add AGENTS.md coordination protocol + CLAUDE.md pointer

Codify ownership zones, label state machine, claim procedure, difficulty
grades, and duplicate-prevention rules as the tool-agnostic SSOT for all
coding agents. CLAUDE.md is a thin pointer to AGENTS.md.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Rust CI 워크플로 추가

**Files:**
- 생성: `.github/workflows/rust.yml`

- [ ] **Step 1: `rust.yml` 생성**

Create `.github/workflows/rust.yml`:
```yaml
name: Rust

on:
  pull_request:
  push:
    branches: [main]

jobs:
  build-test:
    name: Build, test, format
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: cargo build --workspace --verbose

      - name: Test
        run: cargo test --workspace --verbose

      - name: Format check
        run: cargo fmt --all -- --check
```

> ubuntu-latest 러너에는 stable Rust(cargo, rustfmt 컴포넌트)가 사전 설치되어 있어 별도 toolchain 설치 스텝이 불필요하다. `lint.yml`(Swift)과 `release.yml`(macOS 릴리스)은 이미 Task 2에서 처리했거나 무수정이다.

- [ ] **Step 2: YAML 유효성 확인**

Run:
```bash
ls -la .github/workflows/rust.yml && cargo build --workspace 2>&1 | tail -2
```
Expected: 파일 존재, 로컬 cargo build가 `rust.yml`이 돌릴 명령과 동일하게 green(워크플로 명령의 로컬 대리 검증).

- [ ] **Step 3: 커밋**

```bash
git add .github/workflows/rust.yml
git commit -m "ci(rust): add cargo build/test/fmt workflow on ubuntu

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: GitHub 라벨 + Epic/이슈 생성 (outward-facing — 실행 시 사용자 확인)

> 이 Task는 GitHub에 쓰기를 수행한다(라벨·이슈 생성). 실행 직전 사용자 확인을 받는다.
> 레포 슬러그는 `yhzion/PortBridge`로 가정한다.

**Files:** 없음 (GitHub 측 변경)

- [ ] **Step 1: 라벨 생성**

Run:
```bash
gh label create "status:ready" --color 0E8A16 --force
gh label create "status:in-progress" --color FBCA04 --force
gh label create "status:blocked" --color B60205 --force
gh label create "status:review" --color 1D76DB --force
gh label create "zone:core" --color 5319E7 --force
gh label create "zone:cli" --color 5319E7 --force
gh label create "zone:tauri" --color 5319E7 --force
gh label create "zone:macos" --color 5319E7 --force
gh label create "zone:ci" --color 5319E7 --force
gh label create "zone:docs" --color 5319E7 --force
gh label create "grade:1" --color C2E0C6 --force
gh label create "grade:2" --color FEF2C0 --force
gh label create "grade:3" --color F9D0C4 --force
gh label create "epic" --color 3E4B9E --force
```
Expected: 각 라벨 생성/갱신 성공.

- [ ] **Step 2: Epic 이슈 생성**

Run:
```bash
gh issue create --title "Epic: 폴리글랏 모노레포 + 병렬 작업 가능한 기반" \
  --label epic \
  --body "설계: docs/superpowers/specs/2026-05-30-polyglot-monorepo-foundation-design.md

서브이슈:
- #1 전략 B 재구성 (serial, blocks all)
- #2 portbridge-core API/타입 정의 (blocks #3,#4)
- #3 CLI 구현 (blocked-by #2)
- #4 Tauri 스캐폴드 (blocked-by #2)
- #5 README/문서 갱신"
```
Expected: Epic 이슈 번호 출력(이하 `<E>`).

- [ ] **Step 3: 서브이슈 #1 (재구성) 생성**

Run:
```bash
gh issue create --title "전략 B 재구성: Swift→apps/macos/ + Rust workspace 골격" \
  --label "status:in-progress,zone:ci,grade:3" \
  --body "설계 §3 참조. 본 PR이 이 이슈를 닫는다.
체크리스트:
- [ ] Swift→apps/macos/ 이동 + 경로 수정 (build+test green)
- [ ] Cargo workspace + Rust 골격 (cargo green, Swift green)
- [ ] AGENTS.md + CLAUDE.md
- [ ] Rust CI
Epic: #<E>"
```
Expected: 이슈 번호 출력(이하 `<N1>`). 이미 작업 중이므로 `status:in-progress`로 생성.

- [ ] **Step 4: 플레이스홀더 서브이슈 #2~#5 생성**

Run:
```bash
gh issue create --title "portbridge-core API/타입 정의" \
  --label "status:blocked,zone:core,grade:3" \
  --body "blocked-by #<N1>. 인터페이스·타입 정의(캐노니컬). 상세 매핑은 별도 브레인스토밍. Epic: #<E>"

gh issue create --title "CLI를 portbridge-core 위에 구현" \
  --label "status:blocked,zone:cli,grade:2" \
  --body "blocked-by core 이슈. Epic: #<E>"

gh issue create --title "Tauri 데스크탑 스캐폴드 (Win/Linux)" \
  --label "status:blocked,zone:tauri,grade:2" \
  --body "blocked-by core 이슈. 수요 검증 후 착수. Epic: #<E>"

gh issue create --title "README/문서 폴리글랏 구조 반영" \
  --label "status:ready,zone:docs,grade:1" \
  --body "단일 zone(docs), 의존성 없음 → 픽업 가능. Epic: #<E>"
```
Expected: 4개 이슈 번호 출력. (core/cli/tauri는 blocked, docs는 ready.)

> GitHub 네이티브 sub-issues/dependencies가 레포 플랜에서 가용하면 본문 텍스트 대신 네이티브 링크로 대체할 수 있다. 가용 여부는 실행 시 확인한다.

---

## Task 7: PR 생성

**Files:** 없음

- [ ] **Step 1: 브랜치 push**

Run:
```bash
git push -u origin worktree-polyglot-monorepo-foundation
```
Expected: 원격 브랜치 생성.

- [ ] **Step 2: PR 생성 (#1 닫음)**

Run (`<N1>`은 Task 6 Step 3의 이슈 번호):
```bash
gh pr create --title "refactor: 폴리글랏 모노레포 기반 (#<N1>)" \
  --body "## 요약
Swift 앱을 \`apps/macos/\`로 이동하고 \`crates/\`에 Rust core/cli 골격을 추가.
\`AGENTS.md\` 조율 규약과 Rust CI를 도입한다.

## 무중단 검증
- Swift build + unit test: 각 단계 후 green (UITests 제외)
- Rust: cargo build/test/fmt green
- swiftformat/swiftlint: 루트에서 무수정 통과

## 비포함 (설계 §6)
- core 로직 포팅, Tauri, FFI 매핑은 후속 이슈

Closes #<N1>"
```
Expected: PR URL 출력.

- [ ] **Step 3: 이슈 #1 라벨을 review로 전환**

Run:
```bash
gh issue edit <N1> --remove-label status:in-progress --add-label status:review
```
Expected: 성공. (머지는 사용자가 수행; 머지 후 §8 규칙대로 #2가 ready로 전환됨.)

---

## Self-Review 결과

- **Spec 커버리지**: §2 구조→Task2/3, §3 실행계획→Task1~5, §4 Epic/zones→Task6, §5 조율규약→Task4(AGENTS.md)/Task6(라벨), §6 범위경계→전체(후속 제외), §7 결정→반영, §5.8 문서수명→본 계획서 헤더 주석으로 자기적용. 갭 없음.
- **Placeholder 스캔**: `<E>`/`<N1>`은 실행 시 채워지는 이슈 번호 변수로, 사용처를 명시함(미정 placeholder 아님). TBD/TODO 없음. 모든 파일은 완전한 내용 포함.
- **타입/명칭 일관성**: `portbridge_core::version()`을 core(Task3 Step3)에서 정의→cli(Task3 Step4)에서 호출, 일치. 라벨명(`status:*`/`zone:*`/`grade:*`)이 AGENTS.md(Task4)·라벨생성(Task6)·이슈생성(Task6)에서 일치. 검증 명령(`-only-testing:PortBridgeTests`)이 Task1/2/AGENTS.md §9에서 일치.
