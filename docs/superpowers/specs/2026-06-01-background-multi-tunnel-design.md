# 백그라운드 다중 터널 — 설계 (Epic #111)

작성일: 2026-06-01
Epic: #111 (CLI ↔ Desktop 기능 패리티) · 선행 결정: #113 (P0-2 실행 모델), #105 (core 터널 API)

## 목표

CLI에서 SSH 로컬 포트포워딩 터널을 **백그라운드로 띄우고, 여러 개를 추적·종료**하는 기능을 추가한다. 명령 종료 후에도 터널이 살아남아야 하며(데몬 없이 detach), `start/stop/ls`로 관리한다.

비목표(v1 제외): launchd/systemd 자동시작, Windows 지원, CLI↔Desktop 상태 공유.

## 배경·근거

- core `tunnel` 모듈(#105)이 무상태·주입형으로 `forward_args`(argv 조립)·`start_forwarding`(spawn + 1500ms settle 조기사망 감지)·`TunnelSpawner`/`TunnelProcess`를 제공한다. 활성 터널 추적은 소비처 몫(core 문서 명시).
- P0-2(#113) 결정: **데몬 없이 detach + PID/state 파일**. PID·스펙을 `<config>/portbridge/tunnels.json`에 기록, `ls`=PID liveness, `stop [--all]`=SIGTERM, 시작 시 죽은 항목 정리.
- 기존 foreground `tunnel <target> -L`(main.rs)은 core `start_forwarding`을 `ProcessTunnelSpawner`로 소비하며 `poll_exit` 폴링으로 Ctrl-C까지 대기한다.

## 핵심 통찰: detach는 핸들 drop만으로 부족하다

백그라운드 터널이 안정적으로 살아남으려면 `ssh -f`가 대신 해주던 **데몬화(daemonization) 책임 2가지**를 직접 져야 한다(self-detach는 PID 신뢰성 때문에 채택 — `ssh -f`는 부모가 즉시 종료해 PID를 잃고 core settle 감지와 충돌):

1. **stderr를 영속 sink로.** 기존 `ProcessTunnelSpawner`는 stderr를 `Stdio::piped()`로 부모에 연결한다. 핸들을 drop해도 ssh는 살지만(Rust는 drop 시 kill 안 함), CLI 종료 후 파이프 read end가 닫혀 ssh가 다음 stderr 쓰기(예: 네트워크 blip 시 `ServerAliveInterval` 타임아웃)에서 EPIPE/SIGPIPE를 맞으면 **터널이 죽거나 진단을 잃는다**. → stderr를 per-tunnel 로그파일로 라우팅.
2. **제어 터미널에서 분리.** 부모 종료엔 nohup이 불필요하지만, **터미널 닫힘(SIGHUP)·Ctrl-C(SIGINT)**는 포그라운드 프로세스 그룹에 전달돼 같은 session/pgroup의 ssh 자식에 도달한다(foreground 경로는 오히려 이를 이용). → 자식을 독립 session으로 분리.

두 책임 모두 **spawn 시점에 fd·session을 정해야** 하므로(사후 변경 불가) 백그라운드 전용 spawner가 필요하다. core `start_forwarding`은 그대로 재사용하고 다른 `TunnelSpawner`/`TunnelProcess`만 주입한다("#105 재사용" 원칙 보존).

## 아키텍처

### 명령 표면

`Commands::Tunnel`을 단수 명령에서 `TunnelCmd` 서브커맨드 그룹으로 재구성한다.

| 명령 | 동작 |
|---|---|
| `tunnel run <target> -L <spec> [-p <port>]` | 기존 foreground (bare `tunnel`에서 이름만 이동) |
| `tunnel start <target> -L <spec> [-p <port>]` | 백그라운드 시작 → detach → `tunnels.json` 기록 → pid·매핑 출력 |
| `tunnel ls [--json]` | 백그라운드 목록 + liveness, DEAD 1회 표시 후 정리 |
| `tunnel stop <local_port>` | 해당 local_port의 live 터널에 SIGTERM, 레코드 제거 |
| `tunnel stop --all` | 모든 live 터널에 SIGTERM, state 초기화 |

`stop`은 **local_port**를 핸들로 사용한다 — 로컬 포트는 동시에 두 번 바인드할 수 없으므로 live 터널의 유일 식별자다.

### 백그라운드 spawner

core `TunnelSpawner`/`TunnelProcess`를 구현하는 `DetachedTunnelSpawner`/`DetachedTunnelProcess` (main.rs):

- spawn `Command`: stdin=`null`, stdout=`null`, **stderr=로그파일** `<config>/portbridge/logs/tunnel-<local_port>.log`(append/create).
- `Command::pre_exec`에서 `libc::setsid()` 호출 → 자식을 새 session 리더로 만들어 제어 터미널·부모 pgroup에서 분리. `pre_exec`는 fork 후·exec 전 자식에서 실행되며 async-signal-safe해야 한다(`setsid` 단일 호출은 안전).
- `DetachedTunnelProcess::poll_exit`: `try_wait`로 종료 확인, 종료 시 로그파일 내용을 사유로 반환 → `start_forwarding`의 1500ms settle 조기사망 감지가 그대로 작동(인증 실패·바인드 충돌 → `ForwardingDiedEarly`).
- `DetachedTunnelProcess::pid`: `Child::id()`.
- `start_forwarding`가 Ok 반환 후 pid를 기록하고 **핸들을 drop**한다. unix `std::process::Child`의 drop은 kill/wait를 하지 않으므로(fd만 정리) ssh는 살아남아 init으로 reparent된다. 명시적으로 `wait()`/`kill()`을 호출하지 않는다.

### 상태 파일 `tunnels.json`

`FileStore`(store.rs)를 키 `"tunnels"`로 재사용 → `<config>/portbridge/tunnels.json`에 기록되고 원자적 temp→rename을 무료로 얻는다. CLI 크레이트에 `serde`(derive feature) 의존을 추가한다(현재 CLI는 serde_json만 의존, DTO는 core에서 옴; 이 레코드는 CLI 고유).

```rust
// 신규 모듈 crates/portbridge-cli/src/tunnels.rs
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct TunnelRecord {
    pid: u32,
    local_port: u16,
    remote_host: String,
    remote_port: u16,
    target: String,    // 표시용 라벨 (user@host:port 또는 name)
    started_at: u64,   // unix epoch 초
}
```

자체완결(self-contained)이라 `ls`가 server를 재해석할 필요가 없다. `started_at`은 CLI에서 `SystemTime::now()`로 채운다(core는 clockless 유지; 기존 `new_server_id`와 동일 패턴).

### 라이프사이클

- **liveness**: `is_alive(pid)` = `libc::kill(pid as i32, 0) == 0` (unix). ESRCH면 죽음.
- **start**:
  1. `resolve_server` + `parse_forward_spec` (기존 함수 재사용).
  2. 죽은 항목 정리(#113: 시작 시 정리).
  3. 살아있는 터널이 같은 local_port를 이미 점유하면 선거부(깔끔한 메시지; 미선거부 시 core 조기사망이 bind 실패로 잡긴 함).
  4. `start_forwarding(&DetachedTunnelSpawner{..}, id, &server, &spec, 1500ms)`.
  5. Ok → 레코드 append·저장, `started pid=<pid>  127.0.0.1:<lp> → <rh>:<rp>` 출력. 핸들 drop.
  6. Err → 사유(로그파일 tail) 출력, exit 1.
- **ls**: load → `partition_alive`로 alive/dead 분할 → 테이블(STATUS 컬럼: `alive`/`dead`) 또는 `--json` 출력 → **alive만 다시 저장**(dead는 표시 후 정리). 빈 목록도 헤더 출력.
- **stop `<local_port>`**: load → local_port 일치 live 레코드 → `libc::kill(pid, SIGTERM)` → 레코드 제거·저장. 미존재 → exit 1.
- **stop `--all`**: 모든 live 레코드에 SIGTERM → state 비움.

### 모듈 경계

- **`tunnels.rs`** (신규): `TunnelRecord`; state `load`/`save`(FileStore 경유); 순수 로직 `add`/`remove_by_local_port`/`partition_alive(records, is_alive_fn) -> (alive, dead)`/`find_live_port_conflict`; libc 래퍼 `is_alive`/`send_sigterm`; 로그파일 경로 helper.
- **`main.rs`**: clap `TunnelCmd` enum; `DetachedTunnelSpawner`/`DetachedTunnelProcess`; 디스패치; 테이블/JSON 포맷(기존 `format_*` 형제로 배치).

## 에러 처리

- core `PortBridgeError` 매핑 재사용. 조기사망 사유는 로그파일에서 읽어 표시.
- 손상된 `tunnels.json` → 에러(덮어쓰기 금지; `load_servers` 정책과 동일).
- `stop` 부재 대상 → 에러 exit 1.
- 로그 디렉터리 생성 실패 → 에러 exit 1.

## 테스트 전략

순수 로직 중심(실 프로세스·실 pid 비의존):

- `TunnelRecord` serde 라운드트립.
- `add` / `remove_by_local_port` (부재 시 no-op 또는 에러 신호).
- `partition_alive(records, |pid| bool)` — **liveness 주입**으로 alive/dead 분할 검증.
- `find_live_port_conflict` — 같은 local_port 충돌 탐지.
- 손상 파일 → 에러.

detach/setsid 자체는 단위 테스트가 비현실적 → **수동 스모크**로 검증·문서화: `tunnel start` 후 터미널을 닫고 새 셸에서 `tunnel ls`로 생존 확인, 포워딩 포트로 실제 연결 확인, `tunnel stop`으로 종료.

## 알려진 한계 (v1 수용)

- **PID 재사용 레이스**: ssh가 죽고 OS가 PID를 재활용하면 `ls`가 alive로, `stop`이 무고한 프로세스를 SIGTERM할 수 있다. 단일 사용자·저확률 → 문서화.
- **동시 start 레이스**: 원자적 rename은 각 쓰기를 원자화하나 read-modify-write 전체는 아니다 → 병렬 `start` 2건이 레코드를 유실해 `stop` 불가한 orphan ssh가 생길 수 있다. 순차/단일 사용자 가정.
- **start 저장 실패 orphan**: ssh가 settle을 살아남은 뒤 `tunnels.json` 저장이 실패하면(저확률 — 원자적 write) 기록되지 않은 live ssh가 남아 CLI로 `stop`할 수 없다. 저확률 수용.
- **Unix 전용**: `/usr/bin/ssh`·시그널·setsid·reparent는 모두 unix.
- launchd/systemd 자동시작은 별도 과제(이번 범위 밖).

## 동반 정리

`tunnel <target> -L` → `tunnel run <target> -L` 파괴적 변경에 따라 README/docs/help 예시/테스트에서 옛 invocation을 일괄 갱신한다(stale 호출 방지).
