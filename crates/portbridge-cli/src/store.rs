//! 저장된 서버의 파일 영속화 — core `Persistence` 경계의 파일 백엔드(zone:cli 내부).
//!
//! P0-1(#112) 결정: OS config 디렉터리 하위 `portbridge/`에 core `SERVERS_KEY` JSON으로
//! 저장한다. Desktop(UserDefaults)과는 비공유. 쓰기는 temp→rename으로 원자적.
//! 경로 해석은 `std::env`만 사용해 새 의존성(루트 Cargo.toml = serial-only)을 피한다.
//!
//! 순수 로직(중복 검사·조회·serde)과 I/O(`FileStore`)를 분리해 테스트 가능하게 둔다.

use std::path::PathBuf;
use std::{env, fs};

use portbridge_core::model::Server;
use portbridge_core::persistence::{
    Favorite, Persistence, PersistenceError, FAVORITES_KEY, SERVERS_KEY,
};

// ── 경로 해석 (I/O 경계) ──────────────────────────────────────────────────

/// 서버 저장 디렉터리. macOS는 `~/Library/Application Support/PortBridge`,
/// 그 외는 `$XDG_CONFIG_HOME/portbridge`(없으면 `$HOME/.config/portbridge`).
pub fn config_dir() -> PathBuf {
    if cfg!(target_os = "macos") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join("Library/Application Support/PortBridge");
        }
    }
    if let Some(xdg) = env::var_os("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg).join("portbridge");
        }
    }
    if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home).join(".config/portbridge");
    }
    PathBuf::from(".portbridge")
}

// ── 파일 백엔드 ───────────────────────────────────────────────────────────

/// 키→`<dir>/<key>.json` 파일로 매핑하는 [`Persistence`] 구현.
pub struct FileStore {
    dir: PathBuf,
}

impl FileStore {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    fn path_for(&self, key: &str) -> PathBuf {
        // 키에 경로 구분자가 섞여도 디렉터리를 벗어나지 않도록 치환.
        let safe = key.replace(['/', '\\'], "_");
        self.dir.join(format!("{safe}.json"))
    }
}

impl Persistence for FileStore {
    fn load(&self, key: &str) -> Result<Option<String>, PersistenceError> {
        match fs::read_to_string(self.path_for(key)) {
            Ok(s) => Ok(Some(s)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(PersistenceError(e.to_string())),
        }
    }

    fn save(&self, key: &str, value: &str) -> Result<(), PersistenceError> {
        fs::create_dir_all(&self.dir).map_err(|e| PersistenceError(e.to_string()))?;
        let path = self.path_for(key);
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, value).map_err(|e| PersistenceError(e.to_string()))?;
        // 원자적 교체: 같은 디렉터리 내 rename.
        fs::rename(&tmp, &path).map_err(|e| PersistenceError(e.to_string()))?;
        Ok(())
    }
}

// ── 서버 목록 (de)직렬화 ──────────────────────────────────────────────────

/// 저장된 서버 목록을 읽는다. 파일 부재 → 빈 목록. 손상 → 에러(데이터를 덮어쓰지 않기 위함).
pub fn load_servers(p: &dyn Persistence) -> Result<Vec<Server>, String> {
    match p.load(SERVERS_KEY).map_err(|e| e.to_string())? {
        Some(json) => {
            serde_json::from_str(&json).map_err(|e| format!("저장된 서버 목록이 손상됨: {e}"))
        }
        None => Ok(Vec::new()),
    }
}

/// 서버 목록을 저장한다(core Swift 호환 JSON 형태).
pub fn save_servers(p: &dyn Persistence, servers: &[Server]) -> Result<(), String> {
    let json = serde_json::to_string(servers).map_err(|e| e.to_string())?;
    p.save(SERVERS_KEY, &json).map_err(|e| e.to_string())
}

// ── 순수 로직 ─────────────────────────────────────────────────────────────

/// `(user, host, port)` 3튜플이 동일한 서버가 이미 있는지 검사
/// (Desktop `ServerStore.isDuplicate`와 동치 — 같은 host에 다른 user/port는 허용).
pub fn is_duplicate(servers: &[Server], user: &str, host: &str, port: u16) -> bool {
    servers
        .iter()
        .any(|s| s.user == user && s.host == host && s.port == port)
}

/// 식별자(id 또는 name)로 서버를 찾는다.
pub fn find<'a>(servers: &'a [Server], ident: &str) -> Option<&'a Server> {
    servers
        .iter()
        .find(|s| s.id == ident || s.name.as_deref() == Some(ident))
}

// ── 즐겨찾기 목록 (de)직렬화 ──────────────────────────────────────────────
//
// core `Favorite{server_id, remote_port}` + `FAVORITES_KEY`를 그대로 소비한다. JSON 키는
// core serde가 camelCase(serverId/remotePort)로 직렬화한다(servers와 동일 규약).
//
// 주의: CLI와 Desktop은 **저장소 비공유**(CLI=파일, Desktop=UserDefaults — P0-1)이며
// `server_id` 체계도 다르다(CLI는 `srv-<nanos>` 문자열, Desktop `FavoriteKey.serverId`는
// UUID). 따라서 한쪽 데이터를 다른 쪽이 읽도록 의도하지 않는다 — 키 이름만 같을 뿐
// 값 수준 cross-app 호환은 아니다(크로스앱 동기화는 향후 별도 과제).

/// 저장된 즐겨찾기 목록을 읽는다. 파일 부재 → 빈 목록. 손상 → 에러(load_servers와 동일 정책).
pub fn load_favorites(p: &dyn Persistence) -> Result<Vec<Favorite>, String> {
    match p.load(FAVORITES_KEY).map_err(|e| e.to_string())? {
        Some(json) => {
            serde_json::from_str(&json).map_err(|e| format!("저장된 즐겨찾기 목록이 손상됨: {e}"))
        }
        None => Ok(Vec::new()),
    }
}

/// 즐겨찾기 목록을 저장한다(core Swift 호환 JSON 형태).
pub fn save_favorites(p: &dyn Persistence, favorites: &[Favorite]) -> Result<(), String> {
    let json = serde_json::to_string(favorites).map_err(|e| e.to_string())?;
    p.save(FAVORITES_KEY, &json).map_err(|e| e.to_string())
}

/// `(server_id, remote_port)`가 동일한 즐겨찾기가 이미 있는지 검사
/// (Swift `FavoriteKey` 동치 — 같은 서버의 다른 포트는 별개 즐겨찾기).
pub fn is_favorite_duplicate(favorites: &[Favorite], server_id: &str, remote_port: u16) -> bool {
    favorites
        .iter()
        .any(|f| f.server_id == server_id && f.remote_port == remote_port)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn server(id: &str, name: Option<&str>, user: &str, host: &str, port: u16) -> Server {
        Server {
            id: id.to_string(),
            name: name.map(str::to_string),
            user: user.to_string(),
            host: host.to_string(),
            port,
        }
    }

    fn temp_store() -> (FileStore, PathBuf) {
        // tempfile 크레이트 없이: temp_dir + pid + 카운터로 유일 경로.
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let n = N.fetch_add(1, Ordering::Relaxed);
        let dir = env::temp_dir().join(format!("pb_store_{}_{}", std::process::id(), n));
        let _ = fs::remove_dir_all(&dir);
        (FileStore::new(dir.clone()), dir)
    }

    // ── FileStore (I/O) ──────────────────────────────────────────────────

    #[test]
    fn load_missing_returns_none() {
        let (store, dir) = temp_store();
        assert_eq!(store.load(SERVERS_KEY).unwrap(), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_then_load_roundtrips() {
        let (store, dir) = temp_store();
        store.save(SERVERS_KEY, "[]").unwrap();
        assert_eq!(store.load(SERVERS_KEY).unwrap().as_deref(), Some("[]"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_creates_dir_and_no_tmp_left() {
        let (store, dir) = temp_store();
        store.save(SERVERS_KEY, "[]").unwrap();
        // 원자적 rename 후 .tmp 잔여물이 없어야 한다.
        let tmp = store.path_for(SERVERS_KEY).with_extension("json.tmp");
        assert!(!tmp.exists(), "tmp 파일이 남아있음");
        assert!(store.path_for(SERVERS_KEY).exists());
        let _ = fs::remove_dir_all(&dir);
    }

    // ── load/save servers (serde 경계) ───────────────────────────────────

    #[test]
    fn load_servers_missing_is_empty() {
        let (store, dir) = temp_store();
        assert_eq!(load_servers(&store).unwrap(), vec![]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_then_load_servers_roundtrips() {
        let (store, dir) = temp_store();
        let servers = vec![
            server("id-1", Some("prod"), "ubuntu", "10.0.0.1", 2222),
            server("id-2", None, "deploy", "10.0.0.2", 22),
        ];
        save_servers(&store, &servers).unwrap();
        assert_eq!(load_servers(&store).unwrap(), servers);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_servers_corrupt_is_error_not_silent_empty() {
        let (store, dir) = temp_store();
        store.save(SERVERS_KEY, "{ not valid json").unwrap();
        assert!(
            load_servers(&store).is_err(),
            "손상 파일은 에러여야 함(자동 비우기 금지)"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    // ── 순수 로직 ─────────────────────────────────────────────────────────

    #[test]
    fn duplicate_exact_tuple_is_detected() {
        let servers = vec![server("a", None, "u", "h", 22)];
        assert!(is_duplicate(&servers, "u", "h", 22));
    }

    #[test]
    fn same_host_different_user_or_port_is_not_duplicate() {
        let servers = vec![server("a", None, "u", "h", 22)];
        assert!(!is_duplicate(&servers, "u2", "h", 22));
        assert!(!is_duplicate(&servers, "u", "h", 2222));
    }

    #[test]
    fn find_matches_id_or_name() {
        let servers = vec![server("id-1", Some("prod"), "u", "h", 22)];
        assert_eq!(
            find(&servers, "id-1").map(|s| &s.id),
            Some(&"id-1".to_string())
        );
        assert_eq!(
            find(&servers, "prod").map(|s| &s.id),
            Some(&"id-1".to_string())
        );
        assert!(find(&servers, "absent").is_none());
    }

    // ── 즐겨찾기 ───────────────────────────────────────────────────────────

    fn favorite(server_id: &str, remote_port: u16) -> Favorite {
        Favorite {
            server_id: server_id.to_string(),
            remote_port,
        }
    }

    #[test]
    fn load_favorites_missing_is_empty() {
        let (store, dir) = temp_store();
        assert_eq!(load_favorites(&store).unwrap(), vec![]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_then_load_favorites_roundtrips() {
        let (store, dir) = temp_store();
        let favs = vec![favorite("srv-1", 5432), favorite("srv-2", 6379)];
        save_favorites(&store, &favs).unwrap();
        assert_eq!(load_favorites(&store).unwrap(), favs);
        let _ = fs::remove_dir_all(&dir);
    }

    /// 저장 형태가 Swift `FavoriteStore`와 호환되는 camelCase 키(serverId/remotePort)인지.
    #[test]
    fn favorites_persist_in_swift_camelcase() {
        let (store, dir) = temp_store();
        save_favorites(&store, &[favorite("srv-1", 5432)]).unwrap();
        let raw = store.load(FAVORITES_KEY).unwrap().unwrap();
        assert!(raw.contains("serverId"));
        assert!(raw.contains("remotePort"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_favorites_corrupt_is_error() {
        let (store, dir) = temp_store();
        store.save(FAVORITES_KEY, "{ not valid").unwrap();
        assert!(load_favorites(&store).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn favorite_duplicate_exact_pair_is_detected() {
        let favs = vec![favorite("srv-1", 5432)];
        assert!(is_favorite_duplicate(&favs, "srv-1", 5432));
    }

    #[test]
    fn same_server_different_port_is_not_duplicate() {
        let favs = vec![favorite("srv-1", 5432)];
        assert!(!is_favorite_duplicate(&favs, "srv-1", 6379));
        assert!(!is_favorite_duplicate(&favs, "srv-2", 5432));
    }
}
