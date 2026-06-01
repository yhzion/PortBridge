//! core `tunnel::{TunnelSpawner, TunnelProcess}`의 실 프로세스 구현 + 활성 터널 보유.
//!
//! core는 무상태(#105)라 활성 터널 추적은 소비처 몫이다. [`TunnelRegistry`]가 시작한
//! 터널 핸들을 `HashMap`으로 보유(macOS `TunnelManager`의 dict와 동형)하고,
//! `forwarding_stop`/`forwarding_list`가 이를 조회·종료한다. Tauri는 이 레지스트리를
//! `State<Mutex<TunnelRegistry>>`로 들고 있는다.
//!
//! `ChildTunnelProcess`는 `std::process::Child`를 감싸 `poll_exit`(try_wait+stderr
//! 스냅샷)/`kill`/`pid`를 구현. 새 의존성 없이 `std`만 사용.

use std::collections::HashMap;
use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use portbridge_core::model::Forwarding;
use portbridge_core::model::PortBridgeError;
use portbridge_core::tunnel::{TunnelProcess, TunnelSpawner};

/// `std::process::Child` 기반 [`TunnelProcess`]. stderr는 별도 스레드로 드레인해
/// 조기 사망 시 사유를 스냅샷으로 제공한다(파이프 포화 방지).
pub struct ChildTunnelProcess {
    child: Child,
    pid: u32,
    stderr_handle: Option<std::thread::JoinHandle<String>>,
}

impl ChildTunnelProcess {
    fn new(mut child: Child) -> Self {
        let pid = child.id();
        let stderr_handle = child.stderr.take().map(|mut pipe| {
            std::thread::spawn(move || {
                let mut buf = Vec::new();
                let _ = pipe.read_to_end(&mut buf);
                String::from_utf8_lossy(&buf).into_owned()
            })
        });
        Self {
            child,
            pid,
            stderr_handle,
        }
    }

    /// 드레인 스레드를 join해 지금까지 모인 stderr를 회수한다(프로세스 종료 후 호출).
    fn drain_stderr(&mut self) -> String {
        match self.stderr_handle.take() {
            Some(h) => h.join().unwrap_or_default(),
            None => String::new(),
        }
    }
}

impl TunnelProcess for ChildTunnelProcess {
    fn poll_exit(&mut self) -> Option<String> {
        match self.child.try_wait() {
            Ok(Some(_status)) => Some(self.drain_stderr()),
            Ok(None) => None,
            // wait 자체 실패는 사실상 종료로 간주하고 사유를 싣는다.
            Err(e) => Some(format!("try_wait failed: {e}")),
        }
    }

    fn kill(&mut self) -> std::io::Result<()> {
        self.child.kill()?;
        let _ = self.child.wait(); // 좀비 회수
        Ok(())
    }

    fn pid(&self) -> u32 {
        self.pid
    }
}

/// 앱 종료 등으로 핸들이 드롭될 때 실행 중인 ssh 자식을 reap한다. `std::process::Child`는
/// 드롭 시 자식을 종료하지 않으므로(문서화된 동작) Drop 없이는 고아가 남아 포트를 점유
/// → 재실행 시 충돌한다. 실행 중이면 `kill`+`wait`, 이미 종료면 무시(idempotent).
impl Drop for ChildTunnelProcess {
    fn drop(&mut self) {
        if let Ok(None) = self.child.try_wait() {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

/// ssh를 자식 프로세스로 띄우는 [`TunnelSpawner`].
pub struct ProcessTunnelSpawner;

impl TunnelSpawner for ProcessTunnelSpawner {
    fn spawn(
        &self,
        executable: &str,
        args: &[&str],
    ) -> Result<Box<dyn TunnelProcess>, PortBridgeError> {
        let child = Command::new(executable)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| PortBridgeError::ServerUnreachable {
                host: String::new(),
                reason: format!("ssh 실행 실패: {e}"),
            })?;
        Ok(Box::new(ChildTunnelProcess::new(child)))
    }
}

/// 활성 터널 보유소 — 시작한 핸들을 forwarding id로 추적한다(소비처 상태).
#[derive(Default)]
pub struct TunnelRegistry {
    active: HashMap<String, Box<dyn TunnelProcess>>,
    meta: HashMap<String, Forwarding>,
}

impl TunnelRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// 시작된 터널(핸들+메타)을 등록한다.
    pub fn insert(&mut self, forwarding: Forwarding, process: Box<dyn TunnelProcess>) {
        self.active.insert(forwarding.id.clone(), process);
        self.meta.insert(forwarding.id.clone(), forwarding);
    }

    /// id의 터널을 종료하고 보유에서 제거한다. 없으면 `false`.
    pub fn stop(&mut self, id: &str) -> bool {
        self.meta.remove(id);
        match self.active.remove(id) {
            Some(mut p) => {
                let _ = p.kill();
                true
            }
            None => false,
        }
    }

    /// 현재 보유 중인 포워딩 메타 목록(UI 표시용).
    pub fn list(&self) -> Vec<Forwarding> {
        self.meta.values().cloned().collect()
    }
}

/// 시작된 터널을 레지스트리에 등록한다. 잠금 실패(poison) 시 이미 떠 있는 자식을
/// 고아로 남기지 않도록 `kill`한 뒤 에러를 반환한다(commands 레이어가 Tauri 비의존
/// 로직을 위임받는 지점 — 그래서 free fn).
pub fn register_or_kill(
    tunnels: &Mutex<TunnelRegistry>,
    forwarding: Forwarding,
    mut process: Box<dyn TunnelProcess>,
) -> Result<(), String> {
    match tunnels.lock() {
        Ok(mut guard) => {
            guard.insert(forwarding, process);
            Ok(())
        }
        Err(_) => {
            // 등록 실패 → 이미 떠 있는 자식을 kill해 고아 방지.
            let _ = process.kill();
            Err("터널 레지스트리 잠금 실패".to_string())
        }
    }
}

/// 포워딩 id 생성 — uuid 의존성 없이 nanos 기반(cli `new_server_id` 동형).
pub fn new_forwarding_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("fwd-{nanos:x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use portbridge_core::model::State;

    /// 테스트용 mock 핸들 — kill 호출과 pid를 기록.
    struct MockProc {
        pid: u32,
        killed: std::sync::Arc<std::sync::atomic::AtomicBool>,
    }
    impl TunnelProcess for MockProc {
        fn poll_exit(&mut self) -> Option<String> {
            None
        }
        fn kill(&mut self) -> std::io::Result<()> {
            self.killed
                .store(true, std::sync::atomic::Ordering::Relaxed);
            Ok(())
        }
        fn pid(&self) -> u32 {
            self.pid
        }
    }

    fn forwarding(id: &str) -> Forwarding {
        Forwarding {
            id: id.to_string(),
            server_id: "srv".to_string(),
            remote_port: 5432,
            local_port: 15432,
            state: State::Active,
            activated_at: Some(SystemTime::UNIX_EPOCH),
        }
    }

    #[test]
    fn insert_then_list_returns_meta() {
        let mut reg = TunnelRegistry::new();
        let killed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        reg.insert(
            forwarding("fwd-1"),
            Box::new(MockProc {
                pid: 1,
                killed: killed.clone(),
            }),
        );
        let list = reg.list();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "fwd-1");
    }

    #[test]
    fn stop_kills_handle_and_removes() {
        let mut reg = TunnelRegistry::new();
        let killed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        reg.insert(
            forwarding("fwd-1"),
            Box::new(MockProc {
                pid: 1,
                killed: killed.clone(),
            }),
        );
        assert!(reg.stop("fwd-1"));
        assert!(killed.load(std::sync::atomic::Ordering::Relaxed));
        assert!(reg.list().is_empty());
    }

    #[test]
    fn stop_unknown_id_is_false() {
        let mut reg = TunnelRegistry::new();
        assert!(!reg.stop("absent"));
    }

    #[test]
    fn new_forwarding_id_has_prefix() {
        assert!(new_forwarding_id().starts_with("fwd-"));
    }

    // ── #125-1: 레지스트리 등록 ──────────────────────────────────────────────

    #[test]
    fn register_or_kill_inserts_when_lock_ok() {
        let tunnels = Mutex::new(TunnelRegistry::new());
        let killed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let res = register_or_kill(
            &tunnels,
            forwarding("fwd-1"),
            Box::new(MockProc {
                pid: 1,
                killed: killed.clone(),
            }),
        );
        assert!(res.is_ok());
        assert!(!killed.load(std::sync::atomic::Ordering::Relaxed));
        assert_eq!(tunnels.lock().unwrap().list().len(), 1);
    }

    #[test]
    fn register_or_kill_kills_process_when_lock_poisoned() {
        let tunnels = Mutex::new(TunnelRegistry::new());
        // 가드를 든 채 패닉 → 뮤텍스 poison.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _g = tunnels.lock().unwrap();
            panic!("poison the mutex");
        }));
        let killed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let res = register_or_kill(
            &tunnels,
            forwarding("fwd-1"),
            Box::new(MockProc {
                pid: 1,
                killed: killed.clone(),
            }),
        );
        assert!(res.is_err(), "poison 시 에러를 반환해야 함");
        assert!(
            killed.load(std::sync::atomic::Ordering::Relaxed),
            "등록 실패 경로에서 떠 있는 자식을 kill해야 함(고아 방지)"
        );
    }

    // ── #125-2: ChildTunnelProcess Drop이 자식을 reap ────────────────────────

    #[cfg(unix)]
    #[test]
    fn dropping_child_tunnel_process_kills_child() {
        let child = Command::new("sleep").arg("60").spawn().expect("sleep 실행");
        let pid = child.id();
        drop(ChildTunnelProcess::new(child));
        // Drop은 동기 kill+wait이므로 폴링 없이 즉시 확인 가능.
        let alive = Command::new("kill")
            .arg("-0")
            .arg(pid.to_string())
            .status()
            .expect("kill -0 실행")
            .success();
        assert!(!alive, "drop 시 자식 프로세스({pid})가 종료돼야 함");
    }
}
