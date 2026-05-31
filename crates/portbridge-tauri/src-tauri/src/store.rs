//! 서버·즐겨찾기·환경설정의 파일 영속화 — core `Persistence` 경계의 파일 백엔드.
//!
//! CLI(`crates/portbridge-cli/src/store.rs`, #114)와 **동일 패턴**이지만 zone:cli라
//! import할 수 없어 zone:tauri에 미러한다. 저장 디렉터리는 호출자(Tauri `AppHandle`의
//! `app_config_dir`)가 주입하므로 이 모듈은 Tauri 타입에 의존하지 않고 단위 테스트된다.
//!
//! #112 결정 계승: Desktop(UserDefaults)·CLI와 **비공유**(앱별 독립 저장소). 키/JSON
//! 포맷은 core 상수([`SERVERS_KEY`]/[`FAVORITES_KEY`])를 그대로 써 포맷 호환만 유지.
//! 쓰기는 temp→rename으로 원자적. 경로/IO는 `std`만 사용(새 의존성 회피).

use std::path::PathBuf;
use std::{env, fs};

use portbridge_core::persistence::{
    Favorite, Persistence, PersistenceError, Prefs, Server, FAVORITES_KEY, SERVERS_KEY,
};

/// 환경설정 저장 키 (앱 로컬 — Swift는 개별 UserDefaults라 공유 키 없음).
const PREFS_KEY: &str = "portbridge.prefs";

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

/// app-config dir 미해석 시(테스트/헤드리스) 폴백 디렉터리. `$HOME/.portbridge-tauri`,
/// HOME조차 없으면 상대 경로. 프로덕션 경로는 commands에서 `AppHandle`로 주입한다.
pub fn fallback_dir() -> PathBuf {
    if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home).join(".portbridge-tauri");
    }
    PathBuf::from(".portbridge-tauri")
}

// ── DTO (de)직렬화 — core는 직렬화를 호출자에 위임(trait doc) ──────────────────

/// 저장된 서버 목록. 파일 부재 → 빈 목록. 손상 → 에러(데이터를 덮어쓰지 않기 위함).
pub fn load_servers(p: &dyn Persistence) -> Result<Vec<Server>, String> {
    decode_list(p.load(SERVERS_KEY).map_err(|e| e.to_string())?, "서버 목록")
}

pub fn save_servers(p: &dyn Persistence, servers: &[Server]) -> Result<(), String> {
    let json = serde_json::to_string(servers).map_err(|e| e.to_string())?;
    p.save(SERVERS_KEY, &json).map_err(|e| e.to_string())
}

pub fn load_favorites(p: &dyn Persistence) -> Result<Vec<Favorite>, String> {
    decode_list(p.load(FAVORITES_KEY).map_err(|e| e.to_string())?, "즐겨찾기")
}

pub fn save_favorites(p: &dyn Persistence, favorites: &[Favorite]) -> Result<(), String> {
    let json = serde_json::to_string(favorites).map_err(|e| e.to_string())?;
    p.save(FAVORITES_KEY, &json).map_err(|e| e.to_string())
}

/// 환경설정. 파일 부재 → `Prefs::default()`(Swift 기본값). 손상 → 에러.
pub fn load_prefs(p: &dyn Persistence) -> Result<Prefs, String> {
    match p.load(PREFS_KEY).map_err(|e| e.to_string())? {
        Some(json) => serde_json::from_str(&json).map_err(|e| format!("환경설정이 손상됨: {e}")),
        None => Ok(Prefs::default()),
    }
}

pub fn save_prefs(p: &dyn Persistence, prefs: &Prefs) -> Result<(), String> {
    let json = serde_json::to_string(prefs).map_err(|e| e.to_string())?;
    p.save(PREFS_KEY, &json).map_err(|e| e.to_string())
}

fn decode_list<T: serde::de::DeserializeOwned>(
    raw: Option<String>,
    label: &str,
) -> Result<Vec<T>, String> {
    match raw {
        Some(json) => serde_json::from_str(&json).map_err(|e| format!("저장된 {label}이 손상됨: {e}")),
        None => Ok(Vec::new()),
    }
}

// ── 순수 로직 (cli store.rs와 동치) ───────────────────────────────────────────

/// `(user, host, port)` 3튜플 중복 검사 (Desktop `ServerStore.isDuplicate` 동치).
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

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
        static N: AtomicU32 = AtomicU32::new(0);
        let n = N.fetch_add(1, Ordering::Relaxed);
        let dir = env::temp_dir().join(format!("pb_tauri_store_{}_{}", std::process::id(), n));
        let _ = fs::remove_dir_all(&dir);
        (FileStore::new(dir.clone()), dir)
    }

    #[test]
    fn load_missing_returns_none() {
        let (store, dir) = temp_store();
        assert_eq!(store.load(SERVERS_KEY).unwrap(), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_then_load_roundtrips_and_no_tmp_left() {
        let (store, dir) = temp_store();
        store.save(SERVERS_KEY, "[]").unwrap();
        assert_eq!(store.load(SERVERS_KEY).unwrap().as_deref(), Some("[]"));
        let tmp = store.path_for(SERVERS_KEY).with_extension("json.tmp");
        assert!(!tmp.exists(), "tmp 파일이 남아있음");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn servers_roundtrip_and_missing_is_empty() {
        let (store, dir) = temp_store();
        assert_eq!(load_servers(&store).unwrap(), vec![]);
        let servers = vec![
            server("id-1", Some("prod"), "ubuntu", "10.0.0.1", 2222),
            server("id-2", None, "deploy", "10.0.0.2", 22),
        ];
        save_servers(&store, &servers).unwrap();
        assert_eq!(load_servers(&store).unwrap(), servers);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_servers_is_error_not_silent_empty() {
        let (store, dir) = temp_store();
        store.save(SERVERS_KEY, "{ not json").unwrap();
        assert!(load_servers(&store).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn favorites_roundtrip() {
        let (store, dir) = temp_store();
        let favs = vec![Favorite {
            server_id: "id-1".to_string(),
            remote_port: 5432,
        }];
        save_favorites(&store, &favs).unwrap();
        assert_eq!(load_favorites(&store).unwrap(), favs);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn prefs_missing_is_default_then_roundtrips() {
        let (store, dir) = temp_store();
        assert_eq!(load_prefs(&store).unwrap(), Prefs::default());
        let prefs = Prefs {
            show_in_dock: false,
            launch_at_login: true,
            automatic_update_check_enabled: false,
        };
        save_prefs(&store, &prefs).unwrap();
        assert_eq!(load_prefs(&store).unwrap(), prefs);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn duplicate_and_find_logic() {
        let servers = vec![server("id-1", Some("prod"), "u", "h", 22)];
        assert!(is_duplicate(&servers, "u", "h", 22));
        assert!(!is_duplicate(&servers, "u", "h", 2222));
        assert_eq!(find(&servers, "prod").map(|s| s.id.as_str()), Some("id-1"));
        assert!(find(&servers, "absent").is_none());
    }
}
