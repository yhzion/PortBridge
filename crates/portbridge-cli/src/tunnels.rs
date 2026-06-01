//! 백그라운드 터널의 상태 추적 — CLI 고유(detach 모델, #113). core `tunnel`은
//! 무상태라 활성 터널 추적은 소비처 몫이다. PID·스펙을 `<config>/portbridge/tunnels.json`
//! (FileStore 키 `"tunnels"`)에 영속하고, liveness는 `libc::kill(pid,0)`로 확인한다.
//!
//! 순수 로직(partition/remove)과 libc 래퍼(is_alive/send_sigterm)를 분리해
//! 디스패치를 주입형으로 테스트 가능하게 둔다. Unix 전용(시그널·setsid).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use portbridge_core::persistence::Persistence;

/// `tunnels.json` 저장 키 (FileStore가 `<dir>/tunnels.json`으로 매핑).
pub const TUNNELS_KEY: &str = "tunnels";

/// 백그라운드 터널 1건의 영속 레코드. 자체완결(self-contained)이라 `ls`가 server를
/// 재해석할 필요가 없다. `target`은 표시용 라벨, `started_at`은 unix epoch 초.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TunnelRecord {
    pub pid: u32,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
    pub target: String,
    pub started_at: u64,
}

// ── 영속 (serde 경계, store::FileStore 재사용) ────────────────────────────

/// 저장된 터널 목록을 읽는다. 파일 부재 → 빈 목록. 손상 → 에러(load_servers 정책 동일).
pub fn load(p: &dyn Persistence) -> Result<Vec<TunnelRecord>, String> {
    match p.load(TUNNELS_KEY).map_err(|e| e.to_string())? {
        Some(json) => {
            serde_json::from_str(&json).map_err(|e| format!("저장된 터널 목록이 손상됨: {e}"))
        }
        None => Ok(Vec::new()),
    }
}

/// 터널 목록을 저장한다.
pub fn save(p: &dyn Persistence, records: &[TunnelRecord]) -> Result<(), String> {
    let json = serde_json::to_string(records).map_err(|e| e.to_string())?;
    p.save(TUNNELS_KEY, &json).map_err(|e| e.to_string())
}

// ── 순수 로직 (liveness 주입) ─────────────────────────────────────────────

/// 레코드를 (살아있는 것, 죽은 것)으로 분할한다. liveness 판정은 주입해 테스트 가능.
pub fn partition_alive(
    records: Vec<TunnelRecord>,
    is_alive: impl Fn(u32) -> bool,
) -> (Vec<TunnelRecord>, Vec<TunnelRecord>) {
    records.into_iter().partition(|r| is_alive(r.pid))
}

/// local_port가 일치하는 첫 레코드를 제거한다. 반환: (남은 목록, 제거된 레코드 Option).
pub fn remove_by_local_port(
    records: Vec<TunnelRecord>,
    local_port: u16,
) -> (Vec<TunnelRecord>, Option<TunnelRecord>) {
    let mut removed = None;
    let mut kept = Vec::with_capacity(records.len());
    for r in records {
        if removed.is_none() && r.local_port == local_port {
            removed = Some(r);
        } else {
            kept.push(r);
        }
    }
    (kept, removed)
}

// ── 로그 경로 ─────────────────────────────────────────────────────────────

/// 백그라운드 터널의 stderr 로그파일 경로 `<config>/portbridge/logs/tunnel-<port>.log`.
pub fn log_path(config_dir: &Path, local_port: u16) -> PathBuf {
    config_dir
        .join("logs")
        .join(format!("tunnel-{local_port}.log"))
}

// ── libc 래퍼 (unix) ──────────────────────────────────────────────────────

/// PID가 살아있는지 `kill(pid, 0)`으로 확인한다(시그널 미전송 존재 검사).
#[cfg(unix)]
pub fn is_alive(pid: u32) -> bool {
    // SAFETY: kill(_, 0)은 시그널을 보내지 않고 프로세스 존재·권한만 검사한다.
    unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
}

/// 비-Unix 스텁 — 백그라운드 터널은 Unix 전용이라 비-Unix에선 실제 호출되지 않는다.
#[cfg(not(unix))]
pub fn is_alive(_pid: u32) -> bool {
    false
}

/// PID에 SIGTERM을 보낸다. 성공(또는 이미 종료) 시 true.
#[cfg(unix)]
pub fn send_sigterm(pid: u32) -> bool {
    // SAFETY: 단일 kill 호출. 대상은 우리가 띄운 ssh 자식.
    unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM) == 0 }
}

/// 비-Unix 스텁 — 백그라운드 터널은 Unix 전용이라 비-Unix에선 실제 호출되지 않는다.
#[cfg(not(unix))]
pub fn send_sigterm(_pid: u32) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    // 인메모리 Persistence
    #[derive(Default)]
    struct Mem {
        store: RefCell<HashMap<String, String>>,
    }
    impl Persistence for Mem {
        fn load(
            &self,
            key: &str,
        ) -> Result<Option<String>, portbridge_core::persistence::PersistenceError> {
            Ok(self.store.borrow().get(key).cloned())
        }
        fn save(
            &self,
            key: &str,
            value: &str,
        ) -> Result<(), portbridge_core::persistence::PersistenceError> {
            self.store
                .borrow_mut()
                .insert(key.to_string(), value.to_string());
            Ok(())
        }
    }

    fn rec(pid: u32, local_port: u16) -> TunnelRecord {
        TunnelRecord {
            pid,
            local_port,
            remote_host: "localhost".into(),
            remote_port: 5432,
            target: "deploy@10.0.0.1:22".into(),
            started_at: 1_700_000_000,
        }
    }

    #[test]
    fn record_json_roundtrips() {
        let r = rec(1234, 8080);
        let json = serde_json::to_string(&r).unwrap();
        let back: TunnelRecord = serde_json::from_str(&json).unwrap();
        assert_eq!(r, back);
    }

    #[test]
    fn load_missing_is_empty() {
        let p = Mem::default();
        assert_eq!(load(&p).unwrap(), vec![]);
    }

    #[test]
    fn save_then_load_roundtrips() {
        let p = Mem::default();
        let recs = vec![rec(1, 8080), rec(2, 9090)];
        save(&p, &recs).unwrap();
        assert_eq!(load(&p).unwrap(), recs);
    }

    #[test]
    fn load_corrupt_is_error() {
        let p = Mem::default();
        p.save(TUNNELS_KEY, "{ not valid").unwrap();
        assert!(load(&p).is_err());
    }

    #[test]
    fn partition_alive_splits_by_injected_liveness() {
        let recs = vec![rec(1, 8080), rec(2, 9090), rec(3, 7070)];
        // pid 2만 죽음
        let (alive, dead) = partition_alive(recs, |pid| pid != 2);
        assert_eq!(alive.iter().map(|r| r.pid).collect::<Vec<_>>(), vec![1, 3]);
        assert_eq!(dead.iter().map(|r| r.pid).collect::<Vec<_>>(), vec![2]);
    }

    #[test]
    fn remove_by_local_port_removes_one_and_reports() {
        let recs = vec![rec(1, 8080), rec(2, 9090)];
        let (kept, removed) = remove_by_local_port(recs, 8080);
        assert_eq!(
            kept.iter().map(|r| r.local_port).collect::<Vec<_>>(),
            vec![9090]
        );
        assert_eq!(removed.unwrap().pid, 1);
    }

    #[test]
    fn remove_by_local_port_absent_is_none() {
        let recs = vec![rec(1, 8080)];
        let (kept, removed) = remove_by_local_port(recs, 9999);
        assert_eq!(kept.len(), 1);
        assert!(removed.is_none());
    }

    #[test]
    fn log_path_builds_under_logs_dir() {
        let p = log_path(Path::new("/cfg/portbridge"), 8080);
        assert_eq!(p, PathBuf::from("/cfg/portbridge/logs/tunnel-8080.log"));
    }
}
