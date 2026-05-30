//! 영속화 경계 — 직렬화 DTO + 백엔드 비의존 `Persistence` trait.
//!
//! Swift `ServerStore`/`FavoriteStore`/`AppPreferences`의 **모델·직렬화**를 core로
//! 포팅한다. 실제 백엔드(UserDefaults vs 파일/레지스트리)는 core에 두지 않고,
//! 플랫폼/FFI 소비자가 [`Persistence`]를 구현해 주입한다.
//!
//! 포맷 호환: 기존 Swift 앱이 쓰던 키와 JSON 형태를 유지해 기존 사용자 데이터를
//! 그대로 읽을 수 있게 한다([`SERVERS_KEY`], [`FAVORITES_KEY`]).

use serde::{Deserialize, Serialize};

pub use crate::model::Server;

/// 서버 목록 저장 키 (Swift `ServerStore` 호환). 값은 JSON `[Server]`.
pub const SERVERS_KEY: &str = "portbridge.servers";
/// 즐겨찾기 저장 키 (Swift `FavoriteStore` 호환). 값은 JSON `[Favorite]`.
pub const FAVORITES_KEY: &str = "PortBridge.Favorites.v1";

/// 즐겨찾기 키 — `(서버 id, 원격 포트)`. Swift `FavoriteKey` 매핑.
///
/// JSON 키는 Swift `Codable`과 동일한 camelCase(`serverId`/`remotePort`)로 직렬화한다.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Favorite {
    pub server_id: String,
    pub remote_port: u16,
}

/// 앱 환경설정 DTO. Swift `AppPreferences`의 bool 설정을 core 모델로 묶는다.
///
/// (macOS는 개별 `UserDefaults` 키로 보관 — 그 매핑은 FFI/플랫폼 소비자 몫이다.)
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Prefs {
    pub show_in_dock: bool,
    pub launch_at_login: bool,
    pub automatic_update_check_enabled: bool,
}

impl Default for Prefs {
    /// Swift 기본값: dock 표시 on, 로그인 시 실행 off, 자동 업데이트 확인 on.
    fn default() -> Self {
        Self {
            show_in_dock: true,
            launch_at_login: false,
            automatic_update_check_enabled: true,
        }
    }
}

/// [`Persistence`] 백엔드 오류.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistenceError(pub String);

impl std::fmt::Display for PersistenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "persistence backend error: {}", self.0)
    }
}

impl std::error::Error for PersistenceError {}

/// 키→문자열 저장소 경계. 직렬화된 DTO(JSON 등)를 키로 load/save한다.
///
/// (de)직렬화는 호출측이 담당한다 — 이 trait은 백엔드 저장만 추상화한다.
pub trait Persistence {
    /// 키에 저장된 값을 읽는다. 없으면 `Ok(None)`.
    fn load(&self, key: &str) -> Result<Option<String>, PersistenceError>;

    /// 키에 값을 저장한다(덮어쓰기).
    fn save(&self, key: &str, value: &str) -> Result<(), PersistenceError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    // ── serde 라운드트립 (DTO ↔ JSON) ──────────────────────────────────────

    #[test]
    fn server_json_roundtrip() {
        let servers = vec![
            Server {
                id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
                name: Some("prod".to_string()),
                user: "ubuntu".to_string(),
                host: "10.0.0.1".to_string(),
                port: 2222,
            },
            Server {
                id: "550e8400-e29b-41d4-a716-446655440001".to_string(),
                name: None,
                user: "deploy".to_string(),
                host: "10.0.0.2".to_string(),
                port: 22,
            },
        ];
        let json = serde_json::to_string(&servers).unwrap();
        let back: Vec<Server> = serde_json::from_str(&json).unwrap();
        assert_eq!(servers, back);
    }

    /// `name: None`은 JSON에서 키가 생략된다(Swift nil-omit 호환), 그리고 그 JSON을
    /// 다시 읽으면 `None`으로 복원된다.
    #[test]
    fn server_none_name_is_omitted_and_reparses() {
        let server = Server {
            id: "id".to_string(),
            name: None,
            user: "u".to_string(),
            host: "h".to_string(),
            port: 22,
        };
        let json = serde_json::to_string(&server).unwrap();
        assert!(!json.contains("name"));
        let back: Server = serde_json::from_str(&json).unwrap();
        assert_eq!(server, back);
    }

    /// Swift가 쓴 형태(`name` 키 없음, `id`는 UUID 문자열)를 그대로 역직렬화한다.
    #[test]
    fn server_reads_swift_shape_without_name_key() {
        let swift_json = r#"{"id":"ABC","user":"u","host":"h","port":22}"#;
        let server: Server = serde_json::from_str(swift_json).unwrap();
        assert_eq!(server.name, None);
        assert_eq!(server.host, "h");
        assert_eq!(server.port, 22);
    }

    /// 포트 상한(65535)이 u16로 정확히 라운드트립한다 — core의 u16 한계가 앱의
    /// 최대 포트와 일치함을 못박는다.
    #[test]
    fn server_max_port_roundtrips() {
        let json = r#"{"id":"id","user":"u","host":"h","port":65535}"#;
        let server: Server = serde_json::from_str(json).unwrap();
        assert_eq!(server.port, 65535);
        assert_eq!(
            serde_json::from_str::<Server>(&serde_json::to_string(&server).unwrap()).unwrap(),
            server
        );
    }

    #[test]
    fn favorite_uses_camelcase_keys_and_roundtrips() {
        let fav = Favorite {
            server_id: "srv-1".to_string(),
            remote_port: 5432,
        };
        let json = serde_json::to_string(&fav).unwrap();
        assert!(json.contains("serverId"));
        assert!(json.contains("remotePort"));
        let back: Favorite = serde_json::from_str(&json).unwrap();
        assert_eq!(fav, back);
    }

    #[test]
    fn prefs_default_matches_swift_defaults() {
        let prefs = Prefs::default();
        assert!(prefs.show_in_dock);
        assert!(!prefs.launch_at_login);
        assert!(prefs.automatic_update_check_enabled);
    }

    #[test]
    fn prefs_json_roundtrip() {
        let prefs = Prefs {
            show_in_dock: false,
            launch_at_login: true,
            automatic_update_check_enabled: false,
        };
        let json = serde_json::to_string(&prefs).unwrap();
        let back: Prefs = serde_json::from_str(&json).unwrap();
        assert_eq!(prefs, back);
    }

    // ── Persistence trait (인메모리 fake) ───────────────────────────────────

    /// 단위 테스트용 인메모리 [`Persistence`] 구현.
    #[derive(Default)]
    struct InMemoryPersistence {
        store: RefCell<HashMap<String, String>>,
    }

    impl Persistence for InMemoryPersistence {
        fn load(&self, key: &str) -> Result<Option<String>, PersistenceError> {
            Ok(self.store.borrow().get(key).cloned())
        }
        fn save(&self, key: &str, value: &str) -> Result<(), PersistenceError> {
            self.store
                .borrow_mut()
                .insert(key.to_string(), value.to_string());
            Ok(())
        }
    }

    #[test]
    fn persistence_load_missing_key_is_none() {
        let p = InMemoryPersistence::default();
        assert_eq!(p.load("absent").unwrap(), None);
    }

    #[test]
    fn persistence_save_then_load_roundtrips() {
        let p = InMemoryPersistence::default();
        p.save(SERVERS_KEY, "[]").unwrap();
        assert_eq!(p.load(SERVERS_KEY).unwrap().as_deref(), Some("[]"));
    }

    /// DTO를 직렬화해 저장하고, 다시 읽어 역직렬화하면 동일하다(경계 end-to-end).
    #[test]
    fn persistence_stores_serialized_servers() {
        let p = InMemoryPersistence::default();
        let servers = vec![Server {
            id: "id".to_string(),
            name: Some("n".to_string()),
            user: "u".to_string(),
            host: "h".to_string(),
            port: 22,
        }];
        p.save(SERVERS_KEY, &serde_json::to_string(&servers).unwrap())
            .unwrap();
        let loaded: Vec<Server> =
            serde_json::from_str(&p.load(SERVERS_KEY).unwrap().unwrap()).unwrap();
        assert_eq!(servers, loaded);
    }
}
