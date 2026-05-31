//! SSH 포트포워딩 터널의 **실행 경계**. 캐노니컬 `ssh -L` 인자 조립과 시작·조기
//! 사망(early-death) 감지를 core가 단일 소유한다(이전엔 Swift `TunnelManager`와
//! CLI에 중복 구현, #48 단일화).
//!
//! 설계 원칙:
//! - **무상태(stateless) 자유 함수** — `scan()`과 동형. 활성 터널 추적(맵/PID 저장)은
//!   소비처가 보유한다. Tauri는 in-process `HashMap`, CLI는 detach 후 PID 파일(#113)로
//!   서로 다르게 추적하므로 상태를 core에 두면 한쪽에 맞지 않는다.
//! - **주입형 실행 경계** — `scan`의 [`CommandRunner`](crate::scan::CommandRunner)
//!   주입 패턴을 모방한 [`TunnelSpawner`]를 받는다. 단발 request/response인
//!   `CommandRunner`와 달리 터널은 상주 프로세스라, spawn 후 핸들([`TunnelProcess`])을
//!   돌려받아 수명을 관측·종료한다.
//! - **의존성 0개** — `std`만 사용(platform 모듈 원칙). UUID 생성기가 없으므로 포워딩
//!   `id`는 소비처가 주입한다.

use std::time::{Duration, SystemTime};

use crate::model::{Forwarding, PortBridgeError, Server, State};

/// 터널이 사용하는 ssh 실행 파일. `scan`과 동일(절대 경로 고정).
const SSH_EXECUTABLE: &str = "/usr/bin/ssh";

/// 포워딩 1건의 명세(로컬↔원격 포트). `-L <local>:localhost:<remote>` 로 조립된다.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ForwardSpec {
    pub remote_port: u16,
    pub local_port: u16,
}

/// 시작한 터널 자식 프로세스의 핸들 추상화. `std::process::Child`를 감싸되, 테스트에서
/// mock 가능하도록 trait으로 분리한다. 소비처가 이 핸들을 보관해 수명을 추적한다.
pub trait TunnelProcess: Send {
    /// 아직 살아있으면 `None`, 종료했으면 `Some(stderr 스냅샷)`.
    fn poll_exit(&mut self) -> Option<String>;

    /// 프로세스를 종료한다(unix SIGTERM / windows taskkill 상당).
    fn kill(&mut self) -> std::io::Result<()>;

    /// OS 프로세스 ID. 소비처가 detach 추적·저장(#113)에 쓴다.
    fn pid(&self) -> u32;
}

/// 터널 프로세스 spawn 경계. `scan`의 [`CommandRunner`](crate::scan::CommandRunner)와
/// 동형 — 실제 ssh 실행은 소비처(`HostPlatform` 래퍼 등)가 주입한다.
pub trait TunnelSpawner {
    fn spawn(
        &self,
        executable: &str,
        args: &[&str],
    ) -> Result<Box<dyn TunnelProcess>, PortBridgeError>;
}

/// 캐노니컬 `ssh -L` 인자를 조립한다(실행 파일 제외). 이 함수가 Swift/CLI에 흩어져
/// 있던 ssh argv 조립의 단일 출처다.
///
/// 데스크탑(macOS) 동작과 정합: `-L <local>:localhost:<remote>` 로 **원격 머신 자신의**
/// `localhost:remote_port` 에 연결한다. `ExitOnForwardFailure=yes` + `BatchMode=yes` 로
/// 바인드/인증 실패 시 ssh가 즉시 종료해 조기 사망 감지를 가능케 한다.
pub fn forward_args(server: &Server, spec: &ForwardSpec) -> Vec<String> {
    vec![
        "-N".to_string(),
        "-o".to_string(),
        "ExitOnForwardFailure=yes".to_string(),
        "-o".to_string(),
        "ServerAliveInterval=15".to_string(),
        "-o".to_string(),
        "ServerAliveCountMax=3".to_string(),
        "-o".to_string(),
        "BatchMode=yes".to_string(),
        "-o".to_string(),
        "ConnectTimeout=10".to_string(),
        "-p".to_string(),
        server.port.to_string(),
        "-L".to_string(),
        format!("{}:localhost:{}", spec.local_port, spec.remote_port),
        server.ssh_target(),
    ]
}

/// 터널을 시작하고 `settle` 동안 살아남는지 확인한 뒤 [`Forwarding`]과 프로세스 핸들을
/// 돌려준다.
///
/// - `settle` 내에 프로세스가 죽으면 → `Err(PortBridgeError::ForwardingDiedEarly)`
///   (인증 실패·포트 충돌이 여기로 수렴 — macOS의 grace-window와 동일 의미).
/// - 살아남으면 → `Ok((Forwarding { state: Active, .. }, handle))`.
///
/// 무상태: 반환된 핸들의 보관·다중 터널 추적은 호출자 몫. `settle` 동안 블로킹하므로
/// 소비처는 백그라운드 스레드/태스크에서 호출한다(macOS `TunnelManager`·FFI 패턴).
/// `id`는 소비처가 생성해 주입한다(core 의존성 0개 — UUID 생성기 없음).
pub fn start_forwarding<S: TunnelSpawner + ?Sized>(
    spawner: &S,
    id: String,
    server: &Server,
    spec: &ForwardSpec,
    settle: Duration,
) -> Result<(Forwarding, Box<dyn TunnelProcess>), PortBridgeError> {
    let owned = forward_args(server, spec);
    let args: Vec<&str> = owned.iter().map(String::as_str).collect();

    let mut process = spawner.spawn(SSH_EXECUTABLE, &args)?;

    // settle 동안 대기 후 조기 사망 여부 확인. 테스트는 ZERO를 주입해 실제 대기 없이
    // mock 핸들의 programmed poll 결과로 분기를 검증한다.
    std::thread::sleep(settle);
    if let Some(stderr) = process.poll_exit() {
        return Err(PortBridgeError::ForwardingDiedEarly { stderr });
    }

    let forwarding = Forwarding {
        id,
        server_id: server.id.clone(),
        remote_port: spec.remote_port,
        local_port: spec.local_port,
        state: State::Active,
        activated_at: Some(SystemTime::now()),
    };
    Ok((forwarding, process))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// programmed `poll_exit` 시퀀스를 돌려주고 `kill` 호출을 기록하는 mock 핸들.
    struct MockTunnelProcess {
        /// 각 `poll_exit` 호출이 돌려줄 값(앞에서부터 소비). 소진 후엔 `None`(=살아있음).
        exits: RefCell<std::collections::VecDeque<Option<String>>>,
        pid: u32,
        killed: RefCell<bool>,
    }

    impl MockTunnelProcess {
        fn alive(pid: u32) -> Self {
            Self {
                exits: RefCell::new(std::collections::VecDeque::from(vec![None])),
                pid,
                killed: RefCell::new(false),
            }
        }

        fn dead_with(stderr: &str) -> Self {
            Self {
                exits: RefCell::new(std::collections::VecDeque::from(vec![Some(
                    stderr.to_string(),
                )])),
                pid: 4242,
                killed: RefCell::new(false),
            }
        }
    }

    impl TunnelProcess for MockTunnelProcess {
        fn poll_exit(&mut self) -> Option<String> {
            self.exits.borrow_mut().pop_front().flatten()
        }

        fn kill(&mut self) -> std::io::Result<()> {
            *self.killed.borrow_mut() = true;
            Ok(())
        }

        fn pid(&self) -> u32 {
            self.pid
        }
    }

    /// programmed 결과를 돌려주고 받은 argv를 기록하는 mock spawner.
    struct MockSpawner {
        outcome: RefCell<Option<Result<Box<dyn TunnelProcess>, PortBridgeError>>>,
        calls: RefCell<Vec<(String, Vec<String>)>>,
    }

    impl MockSpawner {
        fn returning(process: MockTunnelProcess) -> Self {
            Self {
                outcome: RefCell::new(Some(Ok(Box::new(process)))),
                calls: RefCell::new(Vec::new()),
            }
        }

        fn failing(error: PortBridgeError) -> Self {
            Self {
                outcome: RefCell::new(Some(Err(error))),
                calls: RefCell::new(Vec::new()),
            }
        }
    }

    impl TunnelSpawner for MockSpawner {
        fn spawn(
            &self,
            executable: &str,
            args: &[&str],
        ) -> Result<Box<dyn TunnelProcess>, PortBridgeError> {
            self.calls.borrow_mut().push((
                executable.to_string(),
                args.iter().map(|a| (*a).to_string()).collect(),
            ));
            self.outcome
                .borrow_mut()
                .take()
                .expect("mock spawner outcome already consumed")
        }
    }

    fn server() -> Server {
        Server {
            id: "server-1".to_string(),
            name: None,
            user: "deploy".to_string(),
            host: "10.0.0.1".to_string(),
            port: 2222,
        }
    }

    fn spec() -> ForwardSpec {
        ForwardSpec {
            remote_port: 5432,
            local_port: 15432,
        }
    }

    #[test]
    fn forward_args_builds_canonical_ssh_argv() {
        let args = forward_args(&server(), &spec());

        assert!(args.contains(&"-N".to_string()));
        assert!(args.contains(&"ExitOnForwardFailure=yes".to_string()));
        assert!(args.contains(&"BatchMode=yes".to_string()));
        // -L 매핑: 원격 머신의 localhost:remote_port 로
        assert!(args.contains(&"15432:localhost:5432".to_string()));
        // -p 와 ssh 포트
        let p = args.iter().position(|a| a == "-p").expect("-p present");
        assert_eq!(args[p + 1], "2222");
        // 마지막은 user@host 타깃
        assert_eq!(args.last().unwrap(), "deploy@10.0.0.1");
    }

    #[test]
    fn start_forwarding_active_when_process_survives_settle() {
        let spawner = MockSpawner::returning(MockTunnelProcess::alive(999));

        let (forwarding, handle) = start_forwarding(
            &spawner,
            "fwd-1".to_string(),
            &server(),
            &spec(),
            Duration::ZERO,
        )
        .expect("should start");

        assert_eq!(forwarding.id, "fwd-1");
        assert_eq!(forwarding.server_id, "server-1");
        assert_eq!(forwarding.remote_port, 5432);
        assert_eq!(forwarding.local_port, 15432);
        assert_eq!(forwarding.state, State::Active);
        assert!(forwarding.activated_at.is_some());
        assert_eq!(handle.pid(), 999);
    }

    #[test]
    fn start_forwarding_early_death_maps_to_died_early() {
        let spawner =
            MockSpawner::returning(MockTunnelProcess::dead_with("bind: address already in use"));

        let result = start_forwarding(
            &spawner,
            "fwd-2".to_string(),
            &server(),
            &spec(),
            Duration::ZERO,
        );

        assert_eq!(
            result.err(),
            Some(PortBridgeError::ForwardingDiedEarly {
                stderr: "bind: address already in use".to_string(),
            })
        );
    }

    #[test]
    fn start_forwarding_propagates_spawn_error() {
        let spawner = MockSpawner::failing(PortBridgeError::ServerUnreachable {
            host: "10.0.0.1".to_string(),
            reason: "no route to host".to_string(),
        });

        let result = start_forwarding(
            &spawner,
            "fwd-3".to_string(),
            &server(),
            &spec(),
            Duration::ZERO,
        );

        assert!(matches!(
            result,
            Err(PortBridgeError::ServerUnreachable { host, .. }) if host == "10.0.0.1"
        ));
    }

    #[test]
    fn start_forwarding_passes_ssh_executable_and_canonical_args() {
        let spawner = MockSpawner::returning(MockTunnelProcess::alive(1));

        let _ = start_forwarding(
            &spawner,
            "fwd-4".to_string(),
            &server(),
            &spec(),
            Duration::ZERO,
        )
        .expect("should start");

        let calls = spawner.calls.borrow();
        let (exe, args) = calls.first().expect("spawner should be called");
        assert_eq!(exe, "/usr/bin/ssh");
        assert!(args.iter().any(|a| a == "15432:localhost:5432"));
        assert!(args.iter().any(|a| a == "deploy@10.0.0.1"));
    }

    #[test]
    fn tunnel_process_kill_and_pid_delegate() {
        let mut process = MockTunnelProcess::alive(7777);
        assert_eq!(process.pid(), 7777);
        assert!(process.kill().is_ok());
        assert!(*process.killed.borrow());
    }
}
