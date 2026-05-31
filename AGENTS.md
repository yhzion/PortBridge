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
| `zone:ffi`   | `crates/portbridge-ffi/` |
| `zone:tauri` | `crates/portbridge-tauri/` |
| `zone:macos` | `apps/macos/` |
| `zone:ci`    | `.github/` |
| `zone:docs`  | `docs/`, `README.md` |

### serial-only 공유 파일
다음 파일은 둘 이상의 이슈가 동시에 수정하면 충돌한다. 이를 수정하는 작업은 그
파일을 단독 소유하는 전용 직렬 이슈에서만 처리한다.
- 루트 `Cargo.toml` (workspace members), `Cargo.lock`
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
    + `xcodebuild build-for-testing -project apps/macos/PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS'`
    (테스트 *실행*은 CI에서. 로컬 macOS 26 환경에서는 LaunchServices 이슈로 실행이
    막히므로 `build-for-testing`으로 테스트 타깃 컴파일까지만 로컬 검증한다.)
  - Rust(`zone:core`/`zone:cli`): `cargo build --workspace` + `cargo test --workspace` + `cargo fmt --all -- --check`

## 10. 문서 수명

- **영구(repo)**: 아키텍처, 본 규약, 설계 스펙(`docs/superpowers/specs/`). 불변식만.
- **임시(트리 밖)**: 특정 기능의 구현 계획(`docs/superpowers/plans/`는 gitignore)은
  GitHub 서브이슈 본문 또는 worktree 로컬 파일에 둔다. 머지/close 시 사라져 트리에
  noise를 남기지 않는다.
