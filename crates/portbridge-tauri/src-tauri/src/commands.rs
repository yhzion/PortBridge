//! React가 `invoke`로 호출하는 `#[tauri::command]` 집합 + 프론트 직렬화 DTO.
//!
//! core 도메인 타입 다수(`RemotePort`/`Forwarding`/`State`/`ResolvedHost`)는 `Serialize`를
//! 구현하지 않으므로(FFI 크레이트와 동일 상황) 경계용 DTO로 변환해 내보낸다. `Server`는
//! core가 이미 Serialize/Deserialize라 그대로 입출력에 쓴다.
//!
//! Tauri 결합(AppHandle로 app-config dir 해석, State로 터널 레지스트리 보유)은 이 모듈에
//! 격리하고, 실제 로직은 store/scan_runner/tunnel_runtime 어댑터(Tauri 비의존)가 담당한다.

use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};

use portbridge_core::model::{Forwarding, RemotePort, Server};
use portbridge_core::platform::HostPlatform;
use portbridge_core::scan::{scan, DEFAULT_PORT_RANGE};
use portbridge_core::ssh_config::{resolve_host, ResolvedHost};
use portbridge_core::tunnel::{forward_args, start_forwarding, ForwardSpec};

use crate::scan_runner::ProcessRunner;
use crate::store::{self, FileStore};
use crate::tunnel_runtime::{
    new_forwarding_id, register_or_kill, ProcessTunnelSpawner, TunnelRegistry,
};

/// 활성 터널 레지스트리 — `tauri::State`로 보유(소비처 상태, core는 무상태).
pub struct AppState {
    pub tunnels: Mutex<TunnelRegistry>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            tunnels: Mutex::new(TunnelRegistry::new()),
        }
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

// ── 경계 DTO ──────────────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct RemotePortDto {
    pub port: u16,
    pub address: String,
    pub process_name: Option<String>,
}
impl From<RemotePort> for RemotePortDto {
    fn from(p: RemotePort) -> Self {
        Self {
            port: p.port,
            address: p.address,
            process_name: p.process_name,
        }
    }
}

#[derive(Serialize)]
pub struct ResolvedHostDto {
    pub hostname: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_file: Option<String>,
}
impl From<ResolvedHost> for ResolvedHostDto {
    fn from(h: ResolvedHost) -> Self {
        Self {
            hostname: h.hostname,
            user: h.user,
            port: h.port,
            identity_file: h.identity_file,
        }
    }
}

#[derive(Serialize)]
pub struct ForwardingDto {
    pub id: String,
    pub server_id: String,
    pub remote_port: u16,
    pub local_port: u16,
    /// `Active`/`Starting`/`Idle`/`Error: ...` 문자열(프론트 표시용).
    pub state: String,
    /// 활성화 시각(epoch millis). 미설정 시 `None`.
    pub activated_at_ms: Option<u64>,
}
impl From<Forwarding> for ForwardingDto {
    fn from(f: Forwarding) -> Self {
        use portbridge_core::model::State;
        let state = match f.state {
            State::Idle => "Idle".to_string(),
            State::Starting => "Starting".to_string(),
            State::Active => "Active".to_string(),
            State::Error(reason) => format!("Error: {reason}"),
        };
        let activated_at_ms = f.activated_at.and_then(|t| {
            t.duration_since(std::time::UNIX_EPOCH)
                .ok()
                .map(|d| d.as_millis() as u64)
        });
        Self {
            id: f.id,
            server_id: f.server_id,
            remote_port: f.remote_port,
            local_port: f.local_port,
            state,
            activated_at_ms,
        }
    }
}

/// 포워딩 시작 입력(프론트 → 백엔드).
#[derive(Deserialize)]
pub struct ForwardSpecDto {
    pub remote_port: u16,
    pub local_port: u16,
    /// 포워딩 대상 호스트(SSH 서버 입장). 생략 시 `localhost`(기존 동작 호환).
    #[serde(default = "default_remote_host")]
    pub remote_host: String,
}

/// `ForwardSpecDto.remote_host` 기본값 — 원격 머신 자신.
fn default_remote_host() -> String {
    "localhost".to_string()
}

// ── 저장소 헬퍼: AppHandle → FileStore ────────────────────────────────────

/// app-config dir 하위에 FileStore를 연다. 경로 해석 실패 시 폴백 디렉터리.
/// (트레이 메뉴 핸들러(lib.rs)도 prefs를 읽고 써야 해 `pub(crate)`.)
pub(crate) fn open_store(app: &AppHandle) -> FileStore {
    let dir = app
        .path()
        .app_config_dir()
        .unwrap_or_else(|_| store::fallback_dir());
    FileStore::new(dir)
}

// ── 커맨드 ─────────────────────────────────────────────────────────────────

/// 아키텍처 검증용(기존). core 버전 문자열.
#[tauri::command]
pub fn core_version() -> String {
    portbridge_core::version().to_string()
}

/// 원격 서버의 수신 포트를 스캔한다.
#[tauri::command]
pub fn scan_ports(server: Server) -> Result<Vec<RemotePortDto>, String> {
    scan(&ProcessRunner, &server, DEFAULT_PORT_RANGE)
        .map(|ports| ports.into_iter().map(RemotePortDto::from).collect())
        .map_err(|e| e.to_string())
}

/// `~/.ssh/config`의 Host alias를 해석한다.
#[tauri::command]
pub fn resolve_alias(alias: String) -> Result<Option<ResolvedHostDto>, String> {
    resolve_host(&HostPlatform, &alias)
        .map(|opt| opt.map(ResolvedHostDto::from))
        .map_err(|e| e.to_string())
}

// 서버 CRUD ─────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn server_list(app: AppHandle) -> Result<Vec<Server>, String> {
    store::load_servers(&open_store(&app))
}

#[tauri::command]
pub fn server_save(app: AppHandle, servers: Vec<Server>) -> Result<(), String> {
    store::save_servers(&open_store(&app), &servers)
}

// 즐겨찾기 ───────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn favorites_list(
    app: AppHandle,
) -> Result<Vec<portbridge_core::persistence::Favorite>, String> {
    store::load_favorites(&open_store(&app))
}

#[tauri::command]
pub fn favorites_save(
    app: AppHandle,
    favorites: Vec<portbridge_core::persistence::Favorite>,
) -> Result<(), String> {
    store::save_favorites(&open_store(&app), &favorites)
}

// 환경설정 ───────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn prefs_load(app: AppHandle) -> Result<portbridge_core::persistence::Prefs, String> {
    store::load_prefs(&open_store(&app))
}

#[tauri::command]
pub fn prefs_save(
    app: AppHandle,
    prefs: portbridge_core::persistence::Prefs,
) -> Result<(), String> {
    store::save_prefs(&open_store(&app), &prefs)
}

// 포워딩 ─────────────────────────────────────────────────────────────────────

/// 레지스트리 상태에서 active 여부를 파생해 트레이 아이콘을 갱신한다(#133).
/// 잠금 실패 시 아이콘 갱신만 건너뛴다(기능 동작에 영향 없음).
fn refresh_tray_icon(app: &AppHandle, state: &State<AppState>) {
    if let Ok(reg) = state.tunnels.lock() {
        crate::native_policy::update_tray_icon(app, crate::native_policy::any_active(&reg.list()));
    }
}

/// 터널을 시작한다. settle 동안 살아남으면 활성 레지스트리에 등록하고 메타를 반환.
#[tauri::command]
pub fn forwarding_start(
    app: AppHandle,
    state: State<AppState>,
    server: Server,
    spec: ForwardSpecDto,
) -> Result<ForwardingDto, String> {
    let spec = ForwardSpec {
        remote_port: spec.remote_port,
        local_port: spec.local_port,
        remote_host: spec.remote_host,
    };
    let id = new_forwarding_id();
    let settle = std::time::Duration::from_millis(1500);
    let (forwarding, process) = start_forwarding(&ProcessTunnelSpawner, id, &server, &spec, settle)
        .map_err(|e| e.to_string())?;

    let dto = ForwardingDto::from(forwarding.clone());
    register_or_kill(&state.tunnels, forwarding, process)?;
    refresh_tray_icon(&app, &state);
    Ok(dto)
}

/// id의 터널을 종료한다. 없으면 에러.
#[tauri::command]
pub fn forwarding_stop(app: AppHandle, state: State<AppState>, id: String) -> Result<(), String> {
    let removed = state
        .tunnels
        .lock()
        .map_err(|_| "터널 레지스트리 잠금 실패".to_string())?
        .stop(&id);
    if removed {
        refresh_tray_icon(&app, &state);
        Ok(())
    } else {
        Err(format!("활성 터널 없음: {id}"))
    }
}

/// 현재 활성 터널 목록.
#[tauri::command]
pub fn forwarding_list(state: State<AppState>) -> Result<Vec<ForwardingDto>, String> {
    let list = state
        .tunnels
        .lock()
        .map_err(|_| "터널 레지스트리 잠금 실패".to_string())?
        .list();
    Ok(list.into_iter().map(ForwardingDto::from).collect())
}

/// `forwarding_start`가 등록하는 `forward_args`가 캐노니컬 형태인지 노출 검증
/// (실제 ssh 실행 없이 argv 조립만 — core forward_args 위임 확인).
#[tauri::command]
pub fn forward_args_preview(server: Server, spec: ForwardSpecDto) -> Vec<String> {
    forward_args(
        &server,
        &ForwardSpec {
            remote_port: spec.remote_port,
            local_port: spec.local_port,
            remote_host: spec.remote_host,
        },
    )
}
