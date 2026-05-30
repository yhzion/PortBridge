# 폴리글랏 모노레포 + 병렬 작업 가능한 기반 — 설계

- **상태**: 승인됨 (브레인스토밍 완료, 구현 계획 대기)
- **작성일**: 2026-05-30
- **범위**: PortBridge 레포를 Swift 단일 앱에서 폴리글랏 모노레포(Swift macOS 앱 + Rust core/CLI, 향후 Tauri)로 재구성하고, 여러 코딩 에이전트가 GitHub 이슈를 병렬 픽업하는 표준 조율 체계를 확립한다.

---

## 1. 배경과 목표

현재 레포는 루트에 평탄하게 놓인 Xcode 프로젝트(`PortBridge/`, `PortBridge.xcodeproj`, `PortBridgeTests/` 등)다. 향후 다음을 추가하려 한다.

- **Rust CLI** — 크로스 플랫폼(Linux 배포판/아키텍처, Windows, macOS)
- **Tauri 데스크탑** — Windows/Linux GUI (macOS는 기존 Swift 앱 유지)
- **공유 Rust `core` 크레이트** — SSH config 파싱 / 원격 포트 스캔 / `ssh -L` 터널 생명주기 등 플랫폼 독립 로직의 단일 진실 공급원. 향후 FFI(UniFFI 등)로 Swift 앱까지 먹일 수 있는 "열어둘 문".

이 설계는 그 기반(디렉토리 경계 + 병렬 조율 규칙)을 **무중단으로** 세우는 것을 다룬다.

### 1.1 타협 불가 원칙 (Non-negotiables)

1. **무중단**: 각 단계마다 기존 macOS Swift 빌드 + 유닛 테스트가 green을 유지한다. 베이스라인을 먼저 캡처하고 단계마다 재검증한다.
2. **tool-agnostic**: 조율 규칙은 GitHub Issues + 라벨 + `gh` CLI + `AGENTS.md`(마크다운)로만 표현한다. Claude Code 전용 스킬/훅에 의존하지 않는다 (codex, opencode, pi 등 공용).
3. **병렬 안전**: 공유 경계(디렉토리/크레이트)를 **직렬로 먼저** 세우고, 경계가 선 이후의 작업만 병렬 픽업한다. 경계를 세우는 행위 자체는 병렬화하지 않는다.

> **핵심 통찰**: 재구성은 "병렬화의 대상"이 아니라 "병렬화의 전제"다. 모든 미래 작업이 공유할 경계(디렉토리 레이아웃, 파일 경로, CI)를 바꾸는 작업이므로 직렬로 단 한 번 수행되어야 한다. 경계가 확립된 뒤에야 각 크레이트/디렉토리가 충돌 없는 "소유권 구역(ownership zone)"이 된다.

---

## 2. 타깃 레포 구조

```
PortBridge/
├── apps/macos/                 # 기존 Swift 일체 (git mv)
│   ├── PortBridge/
│   ├── PortBridge.xcodeproj/
│   ├── PortBridgeTests/
│   ├── PortBridgeUITests/
│   └── install.sh              # 함께 이동 (자기위치 기준이라 무수정)
├── crates/
│   ├── portbridge-core/        # lib, 빈 골격 (zone:core)
│   └── portbridge-cli/         # bin, hello-world (zone:cli)
├── Cargo.toml                  # [신규] workspace 루트 (공유/직렬 파일)
├── rustfmt.toml                # [신규]
├── install-release.sh          # 루트 유지·무수정 (공개 URL 계약 보존)
├── .swiftlint.yml              # 루트 유지 (githook 무수정)
├── .swiftformat                # 루트 유지
├── .periphery.yml              # 1줄 수정 (project 경로)
├── AGENTS.md                   # [신규] 조율 표준 규격 (SSOT)
├── CLAUDE.md                   # [신규/얇게] "AGENTS.md를 따르라" 포인터
├── docs/                       # repo-level 문서 (이 설계 포함)
└── .github/workflows/          # lint.yml/release.yml 수정 + Rust job 추가
```

### 2.1 이 구조가 안전한 이유

- **`.xcodeproj` 내부 참조는 안 깨진다**: `project.pbxproj`는 파일을 `SOURCE_ROOT` 기준 상대 경로(`PortBridge/PortBridgeApp.swift` 등)로 참조한다. `PortBridge/` 소스 폴더와 `PortBridge.xcodeproj/`를 **함께** 이동하면 둘 사이의 상대 관계가 보존되어 프로젝트 내부 참조는 한 줄도 안 깨진다. 깨지는 것은 *레포 루트에서 프로젝트를 가리키던 외부 스크립트*뿐이다.
- **lint 설정은 루트 유지**: `swiftformat`/`swiftlint`는 상위 디렉토리로 설정을 자동 탐색하고, `.`가 `.swift` 파일만 매칭하므로 Rust(`.rs`)와 충돌하지 않는다. githooks(`swiftformat --lint .`, `swiftlint`)를 한 줄도 안 고쳐도 된다.
- **`install-release.sh`는 무영향**: GitHub Releases ZIP(`.../releases/latest/download/PortBridge.zip`)을 받아 설치할 뿐, 로컬 프로젝트 경로에 의존하지 않는다. README 공개 one-liner(`curl .../main/install-release.sh`) 계약이 자동 보존된다.
- **`install.sh`는 자기위치 기준**(`cd "$(dirname "$0")"` + `-project PortBridge.xcodeproj`)이라 프로젝트와 같은 폴더(`apps/macos/`)로 함께 옮기면 무수정으로 동작한다.

---

## 3. 재구성 실행 계획 (이슈 #1, 직렬 단일 PR)

각 단계는 독립적으로 green이어야 하며, 그래야 어느 지점이든 안전하게 revert할 수 있다.

| 단계 | 작업 | 검증 게이트 |
|------|------|-------------|
| **Step 0** | 베이스라인 캡처: 현 `main`에서 빌드+테스트 실행 | `xcodebuild build` + `xcodebuild test` green 기록 |
| **Step 1** | `git mv` Swift → `apps/macos/` + 경로의존 파일 수정 (`install.sh` 동반 이동, `.periphery.yml` 1줄, CI working-directory) | `apps/macos`에서 빌드+테스트 green |
| **Step 2** | Cargo workspace + `crates/{core,cli}` 골격 + `rustfmt.toml` | `cargo build` + `cargo test` green, **Swift 여전히 green** |
| **Step 3** | `AGENTS.md` + `CLAUDE.md`(포인터) + 본 설계문서 커밋 | 문서 일관성 셀프리뷰 |
| **Step 4** | CI 갱신: Swift job에 `working-directory: apps/macos`, Rust job 추가 | PR에서 CI 검증 |

→ PR 생성 (`Closes #1`). 머지는 사용자가 수행한다.

> **단계 순서의 근거**: 위험한 이동(Step 1)을 먼저, 순수 추가인 Rust(Step 2)를 나중에. Rust 추가는 기존 Swift를 한 글자도 안 건드리는 additive 변경이라 그 자체로는 빌드를 깰 수 없다. 위험을 앞단계에 격리해 거기서 green을 확인하면, 뒤 단계 실패 시 원인 범위가 좁아진다.

### 3.1 검증 게이트 정의

- **Swift**: `xcodebuild -project apps/macos/PortBridge.xcodeproj -scheme PortBridge build` + `... test`. UITests(`PortBridgeUITests`)는 느리고 환경 의존적이라 게이트에서 제외, 유닛 테스트(`PortBridgeTests`)만 포함한다. (테스트 타깃의 파일 참조가 이동 후 정상인지 잡는 것이 핵심 목적.)
- **Rust**: `cargo build --workspace` + `cargo test --workspace`.
- **로컬 한계**: `periphery`는 로컬 미설치(CI에만 존재). 로컬 게이트는 periphery 제외, CI가 데드코드 검사를 커버한다.

### 3.2 변경 vs 보존 요약

| 항목 | 처리 | 무중단 근거 |
|------|------|-------------|
| `.xcodeproj` 내부 참조 | 무수정 | `SOURCE_ROOT` 상대경로, 소스와 함께 이동 |
| `install-release.sh` + README one-liner | 무수정 | GitHub Releases에서 받음, 로컬경로 무관 |
| `.swiftlint.yml`/`.swiftformat` + githooks | 무수정 | 루트 유지, `.`가 `.swift`만 매칭 |
| `.periphery.yml` | 1줄 수정 | `project` 경로만 |
| `release.yml`/`lint.yml` | `working-directory` 추가 | xcodebuild 실행 위치 |
| `install.sh` | `apps/macos/`로 이동 (무수정) | 자기위치 기준 |

---

## 4. Epic + 서브이슈 분해

```
Epic #E: 폴리글랏 모노레포 + 병렬 작업 가능한 기반
├─ #1 [serial · blocks all][grade:3]  전략 B 재구성 (지금 실행, 경계 확립)
├─ #2 [zone:core][grade:3 · blocks #3,#4]  portbridge-core API/타입 정의
├─ #3 [zone:cli][grade:2 · blocked-by #2]  CLI를 core 위에 구현
├─ #4 [zone:tauri][grade:2 · blocked-by #2]  Tauri 스캐폴드
└─ #5 [zone:docs][grade:1]  README/문서 갱신
```

- `#1`만 본 작업에서 실행한다. `#2~#5`는 **플레이스홀더 이슈**(뼈대만, 상세 매핑은 미룸)로 만들어 의존성만 표시한다.
- `#1`이 머지되어 경계가 확립된 뒤 `#2`(인터페이스 정의)가 픽업 가능해지고, `#2`가 머지되면 `#3`/`#4`가 병렬 픽업 가능해진다.

---

## 5. 조율 표준 규격 (`AGENTS.md`에 명문화)

`AGENTS.md`는 모든 코딩 에이전트(Claude Code / codex / opencode / pi 등)가 세션 시작 시 읽고 따르는 **단일 규칙 출처**다. `CLAUDE.md`는 "AGENTS.md를 따르라"는 얇은 포인터로 두어 출처를 하나로 유지한다. 라벨은 각 에이전트가 `gh` CLI로 **수동 관리**하며, 별도 GitHub Action을 두지 않는다(공유 파일/인프라 최소화, 완전 이식성).

### 5.1 Ownership Zones

각 구역은 자신이 만질 수 있는 경로가 정해진다.

| Zone 라벨 | 경로 |
|-----------|------|
| `zone:core` | `crates/portbridge-core/` |
| `zone:cli` | `crates/portbridge-cli/` |
| `zone:tauri` | `crates/portbridge-tauri/` (향후) |
| `zone:macos` | `apps/macos/` |
| `zone:ci` | `.github/` |
| `zone:docs` | `docs/`, `README.md` |

**serial-only 공유 파일** (둘 이상 이슈가 동시에 만지면 충돌): 루트 `Cargo.toml`(workspace members), `.github/`, `README.md`, lint 설정, `AGENTS.md`. 이들은 전용 직렬 이슈에서만 수정한다. 새 크레이트 추가처럼 workspace 등록이 필요한 작업은 그 등록을 단독으로 소유하는 이슈에서만 처리한다.

### 5.2 픽업 가능(`status:ready`) 5조건

한 이슈가 병렬 픽업 가능하려면 다음을 **모두** 만족해야 한다.

1. **단일 구역만 수정** — 정확히 하나의 ownership zone만 건드린다. 교차 수정 금지.
2. **공유 파일 미수정** — serial-only 파일을 건드리지 않는다.
3. **의존 인터페이스가 이미 머지됨** — `blocked-by`가 전부 closed.
4. **독립 검증 가능** — 그 구역만으로 build + test green.
5. **격리 작업** — 에이전트마다 별도 worktree/브랜치, PR + 검증 게이트로만 머지.

### 5.3 라벨 상태기계

- `status:ready` — 막힌 의존성 없음, 지금 픽업 가능
- `status:in-progress` — 점유됨 (+ assignee 존재)
- `status:blocked` — open인 `blocked-by` 있음
- `status:review` — PR open
- `zone:*` — 5.1의 구역
- `grade:1|2|3` — 5.5의 난이도

### 5.4 점유(claim) 절차 — 레이스 안전

```
1. 조회: gh issue list --label status:ready --search "no:assignee" \
           --json number,title,labels
   → grade ≤ (지시받은 등급) 인 것을 클라이언트 측에서 필터
   (GitHub 라벨은 OR 쿼리가 약하므로 grade 필터는 클라이언트에서 수행)
2. 원자적 점유:
   gh issue edit N --add-assignee @me
   라벨 status:ready → status:in-progress
   댓글: "claimed by <agent-id> at <ISO ts>"   # 감사 로그 + 타이브레이커
3. 재조회(re-read): 같은 창에 다른 에이전트가 점유했으면
   assignee / 댓글 타임스탬프로 진 쪽이 양보하고 다른 이슈로 이동.
```

### 5.5 난이도 grade

grade는 이슈의 **내재적 속성**(난이도 + blast radius)이다. **grade→model 매핑은 repo에 두지 않는다** — 디스패치 시점에 사용자가 결정한다. 에이전트는 "grade N 이하의 픽업 가능한 이슈를 조회"하라는 지시만 받는다.

| 라벨 | 의미 | 예시 |
|------|------|------|
| `grade:1` (mechanical) | 명확히 명세됨, 단일 파일, 설계 결정 없음 | 필드 추가, 경로 수정, 순수함수 테스트 작성 |
| `grade:2` (standard) | 정의된 인터페이스 위 구현, 중간 로직, 단일 구역 | core API 위에 CLI 서브커맨드 구현 |
| `grade:3` (complex/architectural) | 비자명 로직 or 인터페이스·경계 정의 (high blast radius) | `portbridge-core` 타입/트레잇 설계, 파서 알고리즘 |

> grade는 지적 난이도만이 아니라 blast radius를 반영한다. 인터페이스 정의·공유파일 수정처럼 틀리면 남에게 번지는 작업은 어렵지 않아도 high-grade로 분류한다.

### 5.6 중복 구현 방지 (다층 방어)

1. **점유-우선** (5.4) — 이미 점유된 이슈는 시작하지 않는다. 같은 이슈 중복 차단.
2. **1이슈-1구역 + 1이슈-1PR** — 한 구역은 동시에 한 open 이슈만 소유. 교차 중복 구조적 차단.
3. **인터페이스 우선** — 캐노니컬 구현(예: `portbridge-core`의 타입/함수)을 한 번 정의하고 모두가 `use portbridge_core::...`로 의존. Cargo 의존성이 재정의를 컴파일 레벨에서 무의미하게 만든다.
4. **브랜치/워크트리 = 이슈 키** — 브랜치 `issue-N-<slug>`, 이슈당 워크트리 1개. 착수 전 기존 브랜치/PR이 `#N`을 참조하는지 pre-flight 확인.
5. **착수 전 pre-flight 검색** — 만들려는 심볼/기능이 코드베이스나 open PR에 이미 있는지 검색. 없을 때만 작성.
6. **백스톱** — jscpd(중복 탐지)를 CI나 머지 전에 돌려 빠져나간 중복을 잡는다. (예방이 1차, 탐지는 안전망.)

> 중복의 진짜 예방책은 2·3이다. "탐지해서 지운다"가 아니라 "중복을 만들 구조적 기회를 없앤다".

### 5.7 막힘 해제(readiness) 규칙

이슈를 close할 때 그 의존자(dependents)를 검사해, `blocked-by`가 모두 닫힌 이슈를 `status:blocked → status:ready`로 **수동 전환**한다. (GitHub Action 없이 AGENTS.md 규칙으로 운영. 규모가 커져 수동 관리가 아파지면 그때 Action 도입을 검토.)

### 5.8 문서 수명 — 헌법 vs 작업 스펙

| 종류 | 성격 | 수명 | 위치 |
|------|------|------|------|
| 헌법(durable) | 아키텍처, **본 조율 규칙**, ADR — 불변식 | 영구 | repo (`docs/`, `AGENTS.md`) |
| 작업 스펙(ephemeral) | 특정 기능의 구현 계획 — 만드는 과정 | 머지되면 noise | 트리 밖 |

작업 스펙은 **GitHub 서브이슈 본문**(트리에 파일을 안 만듦 → close 시 자동 아카이브, 영구 noise 없음)에 두는 것을 기본으로 한다. 워크트리 로컬 메모가 필요하면 gitignore된 워크트리 로컬 파일로 두어 워크트리 제거 시 함께 사라지게 한다. **헌법 성격(아키텍처·규칙)만 repo에 영구 보존**한다. 본 설계 문서는 경계·규칙을 정의하므로 헌법에 해당하여 repo에 커밋한다.

### 5.9 브랜치/워크트리 규약

- 브랜치: `issue-N-<slug>`
- 이슈당 워크트리 1개, PR로만 머지(검증 게이트 통과 필수)

---

## 6. 실행 범위 경계

- **지금 실행**: 이슈 `#1` 재구성 + `AGENTS.md` + `CLAUDE.md`(포인터) + 본 설계문서. 직렬, 단일 PR.
- **지금 설계만(문서화)**: Epic/zones/조율 프로토콜 전체 → `AGENTS.md`와 본 스펙에 명문화.
- **지금 안 함**: `#2~#5`의 실제 구현, 에이전트 오케스트레이션 자체, FFI(Swift↔Rust core) 매핑.

---

## 7. 결정 기록 (Decisions)

- **재구성 방식**: 전략 B(정식 폴리글랏 모노레포). Swift를 `apps/macos/`로 이동, Rust를 `crates/`에 추가.
- **이번 범위**: 재구성 + Rust 골격(컴파일되는 hello-world 수준). 로직 포팅은 미룸.
- **검증 게이트**: 빌드 + 유닛 테스트 (UITests 제외).
- **git 워크플로**: feature 브랜치 + 단계별 커밋 + PR 생성. 머지는 사용자.
- **SSOT 모델**: 헌법 문서 = repo(권위 출처), GitHub 이슈 = 트래커(체크리스트 + 문서 링크, `Closes #N`).
- **조율 규칙 위치**: `AGENTS.md` (tool-agnostic 표준). `CLAUDE.md`는 얇은 포인터.
- **readiness 관리**: 수동(AGENTS.md 규칙). GitHub Action 미도입.
- **grade**: 이슈에 `grade:1|2|3` 라벨만 부여. grade→model 매핑은 repo에 두지 않고 사용자가 디스패치 시 결정.
- **`install.sh`**: `apps/macos/`로 이동(무수정).

---

## 8. 미해결/후속 (Out of scope, 후속 브레인스토밍 대상)

- `portbridge-core`의 구체적 모듈 경계와 트레잇 시그니처(현 Swift `PortScanner`/`ScanOutputParser`/`TunnelManager`/`SemanticVersion` 등 기준 매핑).
- Tauri 도입 여부 최종 결정(Win/Linux GUI 수요 검증) 및 시스템 트레이 UX.
- FFI(UniFFI/swift-bridge) 통한 macOS Swift 앱의 core 통일 — Tauri로 "core 2벌 유지" 비용이 실재할 때 착수.
- 플랫폼 차이 격리(`platform/unix.rs` vs `platform/windows.rs`): 로컬 `ssh` 호출, 프로세스 종료(시그널 vs `TerminateProcess`), config 경로(`~/.ssh/config` vs `%USERPROFILE%\.ssh\config`).
