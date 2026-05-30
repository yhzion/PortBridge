# Tauri/FFI 전면 통일 설계 — 단일 Rust core (B→A 단계적)

- 상태: 제안(Proposed) — Epic 분해. FFI 바인딩 기술은 **미확정**(FFI-1 spike 결정 사안).
- 작성일: 2026-05-30
- 범위: scan / tunnel(후속) / ssh-config / version / update / storage 도메인의 Rust core 단일화,
  macOS는 FFI 경유 UI 셸로 축소, Tauri(Win·Linux GUI) 신설. 본 스펙은 그 첫 사이클
  (scan·ssh-config·version·update의 core 포팅 + FFI 전환)을 분해한다.
- 선행 스펙: [2026-05-30-polyglot-monorepo-foundation-design.md](./2026-05-30-polyglot-monorepo-foundation-design.md)
  (Epic #27 — 폴리글랏 모노레포/zone/grade/직렬화 기반).

---

## 1. 배경

PortBridge는 현재 두 갈래로 도메인 로직을 중복 보유한다.

- **Rust core** (`crates/portbridge-core/`): 포트 스캔 슬라이스만 포팅 완료
  (`model.rs`의 `Server`/`RemotePort`/`PortBridgeError`(3-variant), `scan.rs`의
  `CommandRunner` trait·`parse_ss`/`parse_lsof`·`scan()`). CLI(`portbridge-cli`)가 이를 소비.
- **macOS Swift 앱** (`apps/macos/PortBridge/`): scan·tunnel·ssh-config·version·update·
  storage 전부를 Swift로 독립 구현(`PortScanner`/`ScanOutputParser`,
  `TunnelManager`/`Forwarding`, `SSHConfigStore`, `SemanticVersion`/`ReleaseFetcher`/
  `UpdateChecker`, `AppPreferences`/`FavoriteStore`/`ServerStore`).

즉 scan은 core와 Swift에 **이중 구현**되어 있고, 나머지 도메인은 Swift 전용이다. 이 상태로는
Win·Linux GUI(Tauri)를 추가할 때 도메인 로직을 또 한 번 중복해야 한다.

## 2. 목표

**단일 Rust core가 CLI / Tauri(Win·Linux GUI) / macOS(FFI 경유)를 모두 먹인다.** macOS Swift는
UI 셸(View/ViewModel/MenuBar/AppDelegate)만 남기고, 도메인 로직은 전부 core로 이관한다(B→A).
한 번에 하지 않고 **모듈별로 `core 포팅 → FFI 교체 → Swift parity 테스트 통과`를 반복**한다.

### 비목표(이번 사이클)
- tunnel(`ssh -L` 생명주기)의 macOS FFI 전환 — core 도메인(#36)·CLI(#41)가 먼저 성숙해야 함.
- storage **백엔드**(UserDefaults/파일/레지스트리)의 FFI 전환 — 이번엔 모델·trait 경계만 정의.
- Tauri GUI 본체 구현 — #31 스캐폴드가 별도 소유. 본 스펙은 크레이트 **등록**까지만 관여.

## 3. 타깃 구조

```
crates/
  portbridge-core/   (zone:core)   model.rs, scan.rs, lib.rs
    + platform/      (FFI-2)        mod.rs, unix.rs, windows.rs   ← OS 격리 경계
    + ssh_config.rs  (CORE-SSH)     Host alias 해석 (core 단독 소유)
    + persistence.rs (CORE-PERSIST) 직렬화 타입 + Persistence trait
    + version.rs     (CORE-VER)     SemVer 파싱/Ord, ReleaseInfo
    + update.rs      (CORE-UPD)     ReleaseFetcher trait + check_update
  portbridge-cli/    (zone:cli)    scan 소비. ssh-config는 CORE-SSH 소비로 재배선(#39/CLI-39-REWIRE)
  portbridge-ffi/    (zone:ffi)    UniFFI|swift-bridge 바인딩 (FFI-1 결정 기술)  [신규]
  portbridge-tauri/  (zone:tauri)  Tauri 데스크탑 (#31 본체) [신규]
apps/macos/          (zone:macos)  UI 셸 + FFI 어댑터 (PortScanner→FFI, SSHConfigStore→FFI, ...)
.github/             (zone:ci)     크로스플랫폼 매트릭스 + FFI 생성 + parity 잡
```

### 신규 zone 라벨
- `zone:ffi` → `crates/portbridge-ffi/` (및 루트 Cargo.toml/Cargo.lock의 ffi/tauri 크레이트 **등록**)

> **REG-* 의 zone 결정 (적대적 검증 반영).** 루트 `Cargo.toml`/`Cargo.lock`은 AGENTS §2 serial-only
> 파일이다. 검증에서 등록 이슈(REG-FFI/REG-TAURI)를 `zone:core`로 두면 도메인 core 스파인
> (FFI-2→…→CORE-UPD)과 **같은 zone에 동시 open**이 가능해져 AGENTS §7.2(같은 zone 동시 open 1개)를
> 위반한다고 지적되었다(serialOnly 플래그는 파일 락만 막고 zone 점유 규칙은 별개).
> 이를 해소하기 위해 REG-FFI/REG-TAURI를 **`zone:core`에서 분리**하고 **`zone:ffi` 스파인에 직렬 편입**
> (FFI-1 → REG-FFI → REG-TAURI → FFI-3)한다. 이로써 core 점유와 무관해지고, ffi zone 내에서도
> 동시 open이 1개를 넘지 않는다.
>
> **권장(사람 결정 필요, §8.3).** 더 깔끔한 분리는 매니페스트 등록 전용 신규 `zone:build`
> (루트 Cargo.toml/Cargo.lock) 도입이다. `zone:build`를 채택하면 REG-* 를 거기로 옮기고 ffi 스파인은
> FFI-1 → FFI-3로 단순화된다. AGENTS.md §2 zone 표 갱신은 별도 직렬 docs/규약 이슈에서 처리.

## 4. 단계 실행계획

| 단계 | 이슈(ref) | zone | grade | 산출물 | 검증 게이트 |
|------|-----------|------|-------|--------|-------------|
| 0. 결정 | FFI-1 | ffi | 3 | FFI 바인딩 기술 결정 + spike PoC + 인터페이스 컨벤션 문서 | spike `cargo build` + PoC `xcodebuild build` |
| 1. 인프라 | FFI-2 | core | 3 | `platform/` 격리 경계(unix/windows) | `cargo build/test/fmt --workspace` |
| 1. 등록 | REG-FFI | ffi | 2 | 루트 Cargo.toml에 portbridge-ffi 등록 + 바인딩 deps 벤더 | `cargo build --workspace` + `fmt --check` |
| 2. core 도메인 | CORE-SSH | core | 3 | ssh-config Host alias 해석(core 소유) + #39 재배선 차단조건 | `cargo build/test/fmt --workspace` |
| 2. cli 재배선 | CLI-39-REWIRE | cli | 1 | #39를 CORE-SSH 소비자로 축소(소유권 이관 강제) | `cargo build/test --workspace` |
| 3. core 도메인 | CORE-PERSIST | core | 3 | 직렬화 타입 + Persistence trait | `cargo build/test/fmt --workspace` |
| 4. core 도메인 | CORE-VER | core | 2 | SemVer/ReleaseInfo | `cargo build/test/fmt --workspace` |
| 5. core 도메인 | CORE-UPD | core | 2 | ReleaseFetcher trait + check_update | `cargo build/test/fmt --workspace` |
| 등록 | REG-TAURI | ffi | 1 | 루트 Cargo.toml에 portbridge-tauri 등록 | `cargo build --workspace` |
| 3. 바인딩 | FFI-3 | ffi | 2 | portbridge-ffi scan() 바인딩 + 에러 3-variant 라운드트립 | `cargo build/test --workspace` + 생성 스크립트 exit 0 |
| 4. macOS 전환 | FFI-SCAN-SWIFT | macos | 2 | scan을 FFI 경유로 + **parity 게이트** | `xcodebuild build` + `build-for-testing` |
| 5. macOS 전환 | FFI-SSH-SWIFT | macos | 2 | ssh-config FFI 경유 + **parity 게이트** | 동상 |
| 6. macOS 전환 | FFI-VER-SWIFT | macos | 2 | version/update FFI 경유 + **parity 게이트** | 동상 |
| CI | CI-1 | ci | 2 | 크로스플랫폼 매트릭스 + FFI 생성 + parity 잡 | CI 워크플로 자체 |

zone별 직렬 스파인(같은 zone 동시 open 1개, blocked-by로 직렬화):
- **zone:core**: (기존 #36) → FFI-2 → CORE-SSH → CORE-PERSIST → CORE-VER → CORE-UPD
- **zone:ffi**: FFI-1 → REG-FFI → REG-TAURI → FFI-3  (등록 이슈를 ffi 스파인에 직렬 편입)
- **zone:macos**: FFI-SCAN-SWIFT → FFI-SSH-SWIFT → FFI-VER-SWIFT
- **zone:cli**: (기존 #37→#38→#39 스파인) — CLI-39-REWIRE는 #39 재배선 노드(CORE-SSH 뒤). #39 자체
  작업과 같은 zone:cli이므로 픽업 시 동시 open 1개 규칙(사람 조율) 준수 필요(§8.5).
- **zone:ci**: CI-1

> **루트 Cargo.toml/Cargo.lock 소유권.** REG-FFI/REG-TAURI/FFI-1/FFI-3가 모두 zone:ffi이지만,
> serial-only 파일(루트 Cargo.toml/Cargo.lock)을 **수정하는 것은 REG-FFI/REG-TAURI 둘 뿐**이고
> 그 둘은 ffi 스파인에서 직렬화되어 동시 수정이 불가능하다. FFI-1(spike, path-only)과 FFI-3(코드만)는
> 루트 매니페스트를 건드리지 않는다.

## 5. Epic + 서브이슈 분해

본 Epic은 **#27의 후속·확장**이며 #27과 상호링크한다. 분해는 미결 플래그를 silent로 두지 않고
결정 사안(FFI 기술)은 grade:3 spike로, 경계 정의(플랫폼/ssh-config/persistence)는 grade:3 core
이슈로, 인터페이스 위 구현은 grade:2로 분리한다.

### 결정/기반 선행
- **FFI-1** [ffi g3] FFI 바인딩 기술 결정 + spike (UniFFI vs swift-bridge). 전 macOS 통일의 루트 게이트.
- **FFI-2** [core g3] 플랫폼 격리(unix/windows). **기존 open #36 뒤로 blocked-by** 하여 zone:core 동시 점유 방지.
- **CORE-SSH** [core g3] ssh-config Host alias 해석을 core가 단독 소유(★#39 재배선의 새 소유자).
- **CORE-PERSIST** [core g3] Persistence trait + 직렬화 타입.
- **CORE-VER** [core g2] SemVer/ReleaseInfo/BundleVersion 도메인.
- **CORE-UPD** [core g2] ReleaseFetcher/UpdateChecker(주입형 HTTP).

### #39 재배선 (그래프 내부 강제 — 더 이상 free-text flag 아님)
- **CLI-39-REWIRE** [cli g1] 기존 #39를 "core ssh_config의 cli 소비자(scan/table에 alias 적용)"로
  본문/제목 축소 + blocked-by에 CORE-SSH 추가. **CORE-SSH의 DoD가 이 재배선 완료를 차단 조건으로
  명기**하여 소유권 이중화를 그래프 안에서 해소.

### 크레이트 등록 (zone:ffi, serial-only 루트 Cargo.toml 전용, ffi 스파인 직렬 편입)
- **REG-FFI** [ffi g2] 루트 Cargo.toml에 portbridge-ffi 등록 + **바인딩 프레임워크 의존성 벤더**
  (Cargo.lock 변동 일괄 흡수). FFI-3는 이 위에서 코드만 작성(신규 외부 deps 미추가).
- **REG-TAURI** [ffi g1] 루트 Cargo.toml에 portbridge-tauri 등록(#31 본체 뒤).

### FFI 바인딩 + macOS parity 전환 (모듈별)
- **FFI-3** [ffi g2] portbridge-ffi scan() 바인딩 + PortBridgeError 3-variant 라운드트립.
- **FFI-SCAN-SWIFT** [macos g2] macOS scan을 FFI 경유로 + parity 게이트(첫 전환, 리스크 최소).
- **FFI-SSH-SWIFT** [macos g2] macOS ssh-config를 FFI 경유로 + parity 게이트.
- **FFI-VER-SWIFT** [macos g2] macOS version/update를 FFI 경유로 + parity 게이트.

### CI
- **CI-1** [ci g2] 크로스플랫폼 Rust 매트릭스 + FFI 바인딩 생성 검증 + Swift parity 테스트 실행 잡.

## 6. parity 게이트(핵심 안전장치)

각 macOS 모듈 전환 이슈(FFI-SCAN/SSH/VER-SWIFT)는 DoD에 **"기존 Swift 동작 == core 경유 동작"**
동치 테스트 통과를 명시한다. 동일 입력에 대한 결과 동치 케이스 테이블이 core 측(포팅 이슈에서
작성)과 Swift 측 양쪽에 존재해야 다음 모듈로 진행한다. 로컬 macOS 26에서는 `build-for-testing`까지,
실제 테스트 **실행**은 CI-1 잡이 담당한다.

또한 FFI 경계 자체의 회귀 검출력을 위해 **FFI-3의 DoD에 PortBridgeError 3-variant가 FFI 경계를
왕복 보존되는지 zone:ffi 단독 라운드트립 테스트**를 필수로 둔다(parity 책임을 macOS로만 미루지 않음).
FFI-3의 "Swift import 실검증"은 macOS 툴체인이 필요하므로 zone:ffi 게이트에서 분리하여
FFI-SCAN-SWIFT/CI-1로 넘긴다(픽업 5조건의 단일-zone 독립 검증 보장).

## 7. 결정 기록

- **전면 통일(B→A 단계적)** — macOS는 UI 셸만, scan/tunnel/ssh/version/update 전부 core. (사용자 확정)
- **SSOT 유지** — Epic + zone/grade 이슈 + `docs/superpowers/specs/` 설계 스펙 + 수동 라벨 + PR/사람-머지.
- **FFI 기술은 미확정** — UniFFI를 권장 출발점으로 보되(Swift 바인딩 성숙도), 확정은 FFI-1 spike의
  측정 근거로만. silent 가정 금지.
- **신규 크레이트(권장)** — `crates/portbridge-ffi/`(core 내 uniffi 모듈이 아니라 독립 크레이트).
- **ssh-config는 core 소유** — 전면 통일이므로 더 이상 cli 전용 아님. cli/#39는 소비자로 축소.
- **storage 경계** — 모델/직렬화는 core, 백엔드(UserDefaults vs 파일/레지스트리)는 플랫폼 주입.
- **등록 이슈는 zone:ffi 스파인 직렬 편입** — 적대적 검증의 §7.2 위반(REG-* 의 zone:core 동시 점유)을
  해소. `zone:build` 신설은 권장 대안으로 남김(§8.3).
- **바인딩 deps는 REG-FFI가 벤더** — Cargo.lock 변동을 등록 이슈에서 일괄 흡수, FFI-3는 코드만 작성하여
  비-serial 이슈가 serial-only Cargo.lock을 건드리지 않게 함(적대적 검증 high 결함 해소).
- **신규 Epic + #27 상호링크** — #27 확장으로 신규 Epic 생성.

## 8. 미해결 / 후속(사람 결정)

1. **FFI 권장안 채택 여부** — UniFFI 출발점 권장이나 FFI-1 spike 결과로 사람이 최종 확정.
2. **신규 Epic 확정** — 본 Epic을 신규로 생성하고 #27과 상호 역링크(수동).
3. **`zone:build` 도입 여부(권장)** — 매니페스트 등록 전용 신규 zone. 채택 시 REG-FFI/REG-TAURI를
   zone:ffi → zone:build로 옮기고 ffi 스파인은 FFI-1 → FFI-3로 단순화. 미채택 시 본 분해대로 ffi
   스파인 직렬 편입 유지. AGENTS.md §2 zone 표 갱신은 별도 직렬 docs/규약 이슈(serial-only).
4. **신규 라벨 생성** — `gh label create zone:ffi` (+ §8.3 채택 시 `zone:build`).
5. **#39 재배선 vs CLI-39-REWIRE** — 본 분해는 CLI-39-REWIRE 노드 + CORE-SSH DoD 차단조건으로 그래프
   내부에서 강제. 다만 CLI-39-REWIRE와 기존 #39 자체 작업이 같은 zone:cli이므로, #39를 별도 신규 이슈로
   둘지 #39 본문 자체를 CLI-39-REWIRE 역할로 전환할지 사람이 결정(zone:cli 동시 open 1개 규칙 준수).
6. **#31 본문** — placeholder → 실제 스펙으로 채우고 "루트 Cargo.toml/Cargo.lock 미수정, 등록은
   REG-TAURI 소관, tauri 미등록 상태에서도 #31 단독 build green(feature gate)"을 명시 조건으로 못박음.
7. **tunnel/storage 백엔드 FFI 전환** — 본 사이클 의도적 제외. #36(tunnel core)·#41(cli tunnel)·
   CORE-PERSIST 성숙 후 후속 Epic 사이클에서 FFI-TUNNEL-SWIFT/FFI-STORE-SWIFT로 추가.
8. **CORE-SSH 신규 error variant** — 파일 없음/파싱 실패 매핑 시 PortBridgeError에 variant 추가가
   필요하면 model.rs 변경 합의(core 타입 재정의 금지, 확장만).
