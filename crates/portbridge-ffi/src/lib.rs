use portbridge_core::model::{PortBridgeError, RemotePort, Server};
use portbridge_core::platform::Platform;
use portbridge_core::scan::{scan, CommandError, CommandResult, CommandRunner, DEFAULT_PORT_RANGE};
use portbridge_core::ssh_config::{resolve_host as core_resolve_host, ResolvedHost};
use portbridge_core::update::{
    check_update as core_check_update, ReleaseFetcher, UpdateError, UpdateStatus,
};
use portbridge_core::version::{
    parse_semver as core_parse_semver, update_available as core_update_available, ReleaseInfo,
    SemanticVersion,
};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

uniffi::setup_scaffolding!();

#[derive(uniffi::Record)]
pub struct RemotePortDto {
    pub port: u16,
    pub address: String,
    pub process_name: Option<String>,
}
impl From<RemotePort> for RemotePortDto {
    fn from(p: RemotePort) -> Self {
        RemotePortDto {
            port: p.port,
            address: p.address,
            process_name: p.process_name,
        }
    }
}

#[derive(Debug, uniffi::Error)]
pub enum PortBridgeFfiError {
    SshAuthFailed { host: String },
    ServerUnreachable { host: String, reason: String },
    RemoteToolsMissing,
    SshConfigNotFound,
    SshConfigUnreadable { reason: String },
}
impl std::fmt::Display for PortBridgeFfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PortBridgeFfiError::SshAuthFailed { host } => write!(f, "ssh auth failed: {host}"),
            PortBridgeFfiError::ServerUnreachable { host, reason } => {
                write!(f, "server unreachable: {host}: {reason}")
            }
            PortBridgeFfiError::RemoteToolsMissing => write!(f, "remote tools missing"),
            PortBridgeFfiError::SshConfigNotFound => write!(f, "ssh config not found"),
            PortBridgeFfiError::SshConfigUnreadable { reason } => {
                write!(f, "ssh config unreadable: {reason}")
            }
        }
    }
}
impl std::error::Error for PortBridgeFfiError {}
impl From<PortBridgeError> for PortBridgeFfiError {
    fn from(e: PortBridgeError) -> Self {
        match e {
            PortBridgeError::SshAuthFailed { host } => PortBridgeFfiError::SshAuthFailed { host },
            PortBridgeError::ServerUnreachable { host, reason } => {
                PortBridgeFfiError::ServerUnreachable { host, reason }
            }
            PortBridgeError::RemoteToolsMissing => PortBridgeFfiError::RemoteToolsMissing,
            // ssh-config 해석 에러는 resolve_host가 방출한다(scan_ports는 미방출).
            PortBridgeError::SshConfigNotFound => PortBridgeFfiError::SshConfigNotFound,
            PortBridgeError::SshConfigUnreadable { reason } => {
                PortBridgeFfiError::SshConfigUnreadable { reason }
            }
            // ForwardingDiedEarly는 scan_ports·resolve_host 둘 다 방출하지 않는다(터널 전용).
            // core 열거형 확장 시 동반 갱신(#65 결합).
            PortBridgeError::ForwardingDiedEarly { .. } => {
                unreachable!("scan_ports/resolve_host never emit ForwardingDiedEarly")
            }
        }
    }
}

#[derive(uniffi::Record)]
pub struct ServerDto {
    pub id: String,
    pub name: Option<String>,
    pub user: String,
    pub host: String,
    pub port: u16,
}
impl From<ServerDto> for Server {
    fn from(s: ServerDto) -> Self {
        Server {
            id: s.id,
            name: s.name,
            user: s.user,
            host: s.host,
            port: s.port,
        }
    }
}

#[derive(uniffi::Record)]
pub struct CommandResultDto {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, uniffi::Error)]
pub enum CommandErrorDto {
    TimedOut,
    LaunchFailed { reason: String },
}
impl std::fmt::Display for CommandErrorDto {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CommandErrorDto::TimedOut => write!(f, "command timed out"),
            CommandErrorDto::LaunchFailed { reason } => {
                write!(f, "command launch failed: {reason}")
            }
        }
    }
}
impl std::error::Error for CommandErrorDto {}
impl From<uniffi::UnexpectedUniFFICallbackError> for CommandErrorDto {
    fn from(e: uniffi::UnexpectedUniFFICallbackError) -> Self {
        CommandErrorDto::LaunchFailed { reason: e.reason }
    }
}

/// Foreign-implemented command runner. Swift injects a concrete runner so the
/// scan crosses the FFI boundary using the host's ssh process.
#[uniffi::export(with_foreign)]
pub trait FfiCommandRunner: Send + Sync {
    fn run(
        &self,
        executable: String,
        args: Vec<String>,
        timeout: Duration,
    ) -> Result<CommandResultDto, CommandErrorDto>;
}

// 어댑터: foreign sync trait(by-value 파라미터) → core sync CommandRunner(&str 경계).
struct Adapter(Arc<dyn FfiCommandRunner>);
impl CommandRunner for Adapter {
    fn run(
        &self,
        executable: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<CommandResult, CommandError> {
        let owned: Vec<String> = args.iter().map(|&a| a.to_string()).collect();
        match self.0.run(executable.to_string(), owned, timeout) {
            Ok(r) => Ok(CommandResult {
                exit_code: r.exit_code,
                stdout: r.stdout,
                stderr: r.stderr,
            }),
            Err(CommandErrorDto::TimedOut) => Err(CommandError::TimedOut),
            Err(CommandErrorDto::LaunchFailed { reason }) => {
                Err(CommandError::LaunchFailed(reason))
            }
        }
    }
}

#[uniffi::export]
pub fn scan_ports(
    runner: Arc<dyn FfiCommandRunner>,
    server: ServerDto,
) -> Result<Vec<RemotePortDto>, PortBridgeFfiError> {
    let ports = scan(&Adapter(runner), &Server::from(server), DEFAULT_PORT_RANGE)?;
    Ok(ports.into_iter().map(RemotePortDto::from).collect())
}

#[derive(uniffi::Record)]
pub struct ResolvedHostDto {
    pub hostname: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_file: Option<String>,
}
impl From<ResolvedHost> for ResolvedHostDto {
    fn from(h: ResolvedHost) -> Self {
        ResolvedHostDto {
            hostname: h.hostname,
            user: h.user,
            port: h.port,
            identity_file: h.identity_file,
        }
    }
}

// resolve_host는 Platform에서 config_dir 경로만 쓰고 파일 I/O는 core가 담당한다.
// 따라서 호출자가 주입한 config_dir만 들고 kill_process는 도달 불가능한 플랫폼.
struct FixedPlatform {
    config_dir: PathBuf,
}
impl Platform for FixedPlatform {
    fn config_dir(&self) -> Option<PathBuf> {
        Some(self.config_dir.clone())
    }
    fn kill_process(&self, _pid: u32) -> std::io::Result<()> {
        unreachable!("resolve_host never kills processes")
    }
}

#[uniffi::export]
pub fn resolve_host(
    config_dir: String,
    alias: String,
) -> Result<Option<ResolvedHostDto>, PortBridgeFfiError> {
    let platform = FixedPlatform {
        config_dir: PathBuf::from(config_dir),
    };
    let resolved = core_resolve_host(&platform, &alias)?;
    Ok(resolved.map(ResolvedHostDto::from))
}

// ── version (trivial — callback 불필요, #85 패턴) ─────────────────────────────

#[derive(uniffi::Record)]
pub struct SemanticVersionDto {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}
impl From<SemanticVersion> for SemanticVersionDto {
    fn from(v: SemanticVersion) -> Self {
        SemanticVersionDto {
            major: v.major,
            minor: v.minor,
            patch: v.patch,
        }
    }
}
impl From<SemanticVersionDto> for SemanticVersion {
    fn from(v: SemanticVersionDto) -> Self {
        SemanticVersion::new(v.major, v.minor, v.patch)
    }
}

#[derive(uniffi::Record)]
pub struct ReleaseInfoDto {
    pub tag_name: String,
    pub name: Option<String>,
    pub html_url: String,
    pub published_at: Option<String>,
    pub body: Option<String>,
}
// ReleaseInfoDto는 경계로 들어오는 방향(Dto→core)만 필요하다(parse 결과/Available는
// SemanticVersionDto로 전달되므로 core→Dto 변환은 어디에서도 쓰이지 않음).
impl From<ReleaseInfoDto> for ReleaseInfo {
    fn from(r: ReleaseInfoDto) -> Self {
        ReleaseInfo {
            tag_name: r.tag_name,
            name: r.name,
            html_url: r.html_url,
            published_at: r.published_at,
            body: r.body,
        }
    }
}

#[uniffi::export]
pub fn parse_semver(input: String) -> Option<SemanticVersionDto> {
    core_parse_semver(&input).map(SemanticVersionDto::from)
}

#[uniffi::export]
pub fn update_available(current: SemanticVersionDto, latest: ReleaseInfoDto) -> bool {
    core_update_available(&current.into(), &latest.into())
}

// ── update (callback — ReleaseFetcher, #58 with_foreign 패턴) ─────────────────

/// FFI 경계의 업데이트 조회 실패 원인. core `UpdateError`(별도 enum, PortBridgeError와
/// 무관)를 미러한다. tuple variant인 core를 struct variant로 노출(uniffi 관례 — 기존
/// CommandErrorDto와 동형).
#[derive(Debug, uniffi::Error)]
pub enum UpdateFfiError {
    Network { reason: String },
    HttpStatus { code: u16 },
    Decoding { reason: String },
    InvalidResponse,
}
impl std::fmt::Display for UpdateFfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UpdateFfiError::Network { reason } => write!(f, "network error: {reason}"),
            UpdateFfiError::HttpStatus { code } => write!(f, "HTTP {code}"),
            UpdateFfiError::Decoding { reason } => write!(f, "decoding error: {reason}"),
            UpdateFfiError::InvalidResponse => write!(f, "invalid response"),
        }
    }
}
impl std::error::Error for UpdateFfiError {}
impl From<UpdateError> for UpdateFfiError {
    fn from(e: UpdateError) -> Self {
        match e {
            UpdateError::Network(reason) => UpdateFfiError::Network { reason },
            UpdateError::HttpStatus(code) => UpdateFfiError::HttpStatus { code },
            UpdateError::Decoding(reason) => UpdateFfiError::Decoding { reason },
            UpdateError::InvalidResponse => UpdateFfiError::InvalidResponse,
        }
    }
}
// 어댑터가 foreign Result(UpdateFfiError)를 core Result(UpdateError)로 되돌리는 데 필요.
impl From<UpdateFfiError> for UpdateError {
    fn from(e: UpdateFfiError) -> Self {
        match e {
            UpdateFfiError::Network { reason } => UpdateError::Network(reason),
            UpdateFfiError::HttpStatus { code } => UpdateError::HttpStatus(code),
            UpdateFfiError::Decoding { reason } => UpdateError::Decoding(reason),
            UpdateFfiError::InvalidResponse => UpdateError::InvalidResponse,
        }
    }
}
// foreign trait의 Result는 콜백 프로토콜 실패를 흡수할 변환이 필수다. 정해진 매핑이
// 없으므로 문자열을 싣는 Network로 흡수한다(기존 CommandErrorDto와 동일한 catch-all 관례).
impl From<uniffi::UnexpectedUniFFICallbackError> for UpdateFfiError {
    fn from(e: uniffi::UnexpectedUniFFICallbackError) -> Self {
        UpdateFfiError::Network { reason: e.reason }
    }
}

/// 업데이트 체크 결과(성공 경로). core `UpdateStatus`의 실패 variant(`Error`)는
/// check_update의 `Err` 가지로 옮겨가므로 DTO는 UpToDate/Available 둘만 미러한다.
#[derive(uniffi::Enum)]
pub enum UpdateStatusDto {
    UpToDate,
    Available {
        version: SemanticVersionDto,
        url: String,
    },
}

/// Foreign-implemented 릴리스 조회기. Swift가 구체 fetcher를 주입해 HTTP 조회가 FFI
/// 경계를 넘게 한다(scan의 FfiCommandRunner와 같은 입장).
#[uniffi::export(with_foreign)]
pub trait FfiReleaseFetcher: Send + Sync {
    fn fetch_latest(&self) -> Result<ReleaseInfoDto, UpdateFfiError>;
}

// 어댑터: foreign sync trait(by-value 반환) → core sync ReleaseFetcher.
struct FetcherAdapter(Arc<dyn FfiReleaseFetcher>);
impl ReleaseFetcher for FetcherAdapter {
    fn fetch_latest(&self) -> Result<ReleaseInfo, UpdateError> {
        match self.0.fetch_latest() {
            Ok(dto) => Ok(dto.into()),
            Err(e) => Err(e.into()),
        }
    }
}

#[uniffi::export]
pub fn check_update(
    fetcher: Arc<dyn FfiReleaseFetcher>,
    current: SemanticVersionDto,
) -> Result<UpdateStatusDto, UpdateFfiError> {
    // core 시그니처는 (current, fetcher) 순서다.
    match core_check_update(&current.into(), &FetcherAdapter(fetcher)) {
        UpdateStatus::UpToDate => Ok(UpdateStatusDto::UpToDate),
        UpdateStatus::Available { version, url } => Ok(UpdateStatusDto::Available {
            version: version.into(),
            url,
        }),
        UpdateStatus::Error(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- DoD2: From<PortBridgeError> payload 보존 (3 variant) ---

    #[test]
    fn from_ssh_auth_failed_preserves_host() {
        let ffi = PortBridgeFfiError::from(PortBridgeError::SshAuthFailed {
            host: "prod".to_string(),
        });
        match ffi {
            PortBridgeFfiError::SshAuthFailed { host } => assert_eq!(host, "prod"),
            other => panic!("expected SshAuthFailed, got {other:?}"),
        }
    }

    #[test]
    fn from_server_unreachable_preserves_host_and_reason() {
        let ffi = PortBridgeFfiError::from(PortBridgeError::ServerUnreachable {
            host: "prod".to_string(),
            reason: "no route to host".to_string(),
        });
        match ffi {
            PortBridgeFfiError::ServerUnreachable { host, reason } => {
                assert_eq!(host, "prod");
                assert_eq!(reason, "no route to host");
            }
            other => panic!("expected ServerUnreachable, got {other:?}"),
        }
    }

    #[test]
    fn from_remote_tools_missing_maps() {
        let ffi = PortBridgeFfiError::from(PortBridgeError::RemoteToolsMissing);
        assert!(matches!(ffi, PortBridgeFfiError::RemoteToolsMissing));
    }

    // --- From<PortBridgeError> ssh-config 보존 (resolve_host가 방출하는 2 variant) ---

    #[test]
    fn from_ssh_config_not_found_maps() {
        let ffi = PortBridgeFfiError::from(PortBridgeError::SshConfigNotFound);
        assert!(matches!(ffi, PortBridgeFfiError::SshConfigNotFound));
    }

    #[test]
    fn from_ssh_config_unreadable_preserves_reason() {
        let ffi = PortBridgeFfiError::from(PortBridgeError::SshConfigUnreadable {
            reason: "x".to_string(),
        });
        match ffi {
            PortBridgeFfiError::SshConfigUnreadable { reason } => assert_eq!(reason, "x"),
            other => panic!("expected SshConfigUnreadable, got {other:?}"),
        }
    }

    // --- seam: scan_ports export 경로를 FfiCommandRunner 주입으로 구동 ---

    /// canned 결과/에러를 그대로 돌려주는 테스트용 러너.
    struct CannedRunner(Result<CommandResultDto, CommandErrorDto>);
    impl FfiCommandRunner for CannedRunner {
        fn run(
            &self,
            _executable: String,
            _args: Vec<String>,
            _timeout: Duration,
        ) -> Result<CommandResultDto, CommandErrorDto> {
            match &self.0 {
                Ok(r) => Ok(CommandResultDto {
                    exit_code: r.exit_code,
                    stdout: r.stdout.clone(),
                    stderr: r.stderr.clone(),
                }),
                Err(CommandErrorDto::TimedOut) => Err(CommandErrorDto::TimedOut),
                Err(CommandErrorDto::LaunchFailed { reason }) => {
                    Err(CommandErrorDto::LaunchFailed {
                        reason: reason.clone(),
                    })
                }
            }
        }
    }

    fn server_dto() -> ServerDto {
        ServerDto {
            id: "deploy@prod".to_string(),
            name: None,
            user: "deploy".to_string(),
            host: "prod".to_string(),
            port: 22,
        }
    }

    #[test]
    fn scan_ports_happy_parses_listen_line() {
        let runner: Arc<dyn FfiCommandRunner> = Arc::new(CannedRunner(Ok(CommandResultDto {
            exit_code: 0,
            stdout: "LISTEN 0 128 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=1,fd=1))\n"
                .to_string(),
            stderr: String::new(),
        })));
        let ports = scan_ports(runner, server_dto()).expect("expected Ok");
        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 8080);
        assert_eq!(ports[0].process_name.as_deref(), Some("nginx"));
    }

    #[test]
    fn scan_ports_ssh_auth_failure_surfaces_via_question_mark() {
        // exit_code 255 + publickey stderr는 core가 SshAuthFailed로 분류한다.
        // scan_ports의 `?`/From<PortBridgeError>가 그 payload를 보존함을 증명.
        let runner: Arc<dyn FfiCommandRunner> = Arc::new(CannedRunner(Ok(CommandResultDto {
            exit_code: 255,
            stdout: String::new(),
            stderr: "Permission denied (publickey).".to_string(),
        })));
        match scan_ports(runner, server_dto()) {
            Err(PortBridgeFfiError::SshAuthFailed { host }) => assert_eq!(host, "prod"),
            Err(other) => panic!("expected SshAuthFailed, got {other:?}"),
            Ok(_) => panic!("expected Err, got Ok"),
        }
    }

    // --- seam: resolve_host export를 config_dir 주입으로 구동 (std만) ---

    /// 고유한 임시 디렉터리를 만든다(테스트 격리 — pid + 고정 접미사).
    fn resolve_temp_dir(tag: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("pb_ffi_resolve_{}_{}", std::process::id(), tag));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test]
    fn resolve_host_returns_some_for_known_alias() {
        let dir = resolve_temp_dir("known");
        std::fs::write(
            dir.join("config"),
            "Host foo\n  HostName 1.2.3.4\n  Port 2222\n",
        )
        .unwrap();

        let resolved = resolve_host(dir.to_str().unwrap().to_string(), "foo".to_string())
            .expect("expected Ok")
            .expect("expected Some");
        assert_eq!(resolved.hostname.as_deref(), Some("1.2.3.4"));
        assert_eq!(resolved.port, Some(2222));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_host_unknown_alias_is_none() {
        let dir = resolve_temp_dir("unknown");
        std::fs::write(
            dir.join("config"),
            "Host foo\n  HostName 1.2.3.4\n  Port 2222\n",
        )
        .unwrap();

        let resolved = resolve_host(dir.to_str().unwrap().to_string(), "nope".to_string())
            .expect("expected Ok");
        assert!(resolved.is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_host_missing_config_file_is_not_found() {
        let dir = resolve_temp_dir("missing");
        // config 파일 없는 빈 디렉터리 → SshConfigNotFound.
        match resolve_host(dir.to_str().unwrap().to_string(), "foo".to_string()) {
            Err(PortBridgeFfiError::SshConfigNotFound) => {}
            Err(other) => panic!("expected SshConfigNotFound, got {other:?}"),
            Ok(_) => panic!("expected SshConfigNotFound, got Ok"),
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    // ── version: parse_semver export ──────────────────────────────────────────

    #[test]
    fn parse_semver_valid_returns_some_components() {
        let v = parse_semver("1.2.3".to_string()).expect("expected Some");
        assert_eq!((v.major, v.minor, v.patch), (1, 2, 3));
    }

    #[test]
    fn parse_semver_strips_leading_v() {
        let v = parse_semver("v2.0.1".to_string()).expect("expected Some");
        assert_eq!((v.major, v.minor, v.patch), (2, 0, 1));
    }

    #[test]
    fn parse_semver_invalid_returns_none() {
        assert!(parse_semver("1.2.3-alpha".to_string()).is_none());
        assert!(parse_semver("nightly".to_string()).is_none());
    }

    // ── version: update_available export ──────────────────────────────────────

    fn release_dto(tag: &str) -> ReleaseInfoDto {
        ReleaseInfoDto {
            tag_name: tag.to_string(),
            name: None,
            html_url: "https://example/r".to_string(),
            published_at: None,
            body: None,
        }
    }

    fn version_dto(major: u32, minor: u32, patch: u32) -> SemanticVersionDto {
        SemanticVersionDto {
            major,
            minor,
            patch,
        }
    }

    #[test]
    fn update_available_true_when_release_is_newer() {
        assert!(update_available(
            version_dto(1, 2, 0),
            release_dto("v1.3.0")
        ));
    }

    #[test]
    fn update_available_false_when_not_newer_or_unparseable() {
        assert!(!update_available(
            version_dto(1, 3, 0),
            release_dto("1.3.0")
        ));
        assert!(!update_available(
            version_dto(1, 0, 0),
            release_dto("nightly")
        ));
    }

    // ── update: From<UpdateError> 각 variant 보존 (4 variant) ──────────────────

    #[test]
    fn from_update_error_preserves_all_variants() {
        match UpdateFfiError::from(UpdateError::Network("offline".to_string())) {
            UpdateFfiError::Network { reason } => assert_eq!(reason, "offline"),
            other => panic!("expected Network, got {other:?}"),
        }
        match UpdateFfiError::from(UpdateError::HttpStatus(503)) {
            UpdateFfiError::HttpStatus { code } => assert_eq!(code, 503),
            other => panic!("expected HttpStatus, got {other:?}"),
        }
        match UpdateFfiError::from(UpdateError::Decoding("bad json".to_string())) {
            UpdateFfiError::Decoding { reason } => assert_eq!(reason, "bad json"),
            other => panic!("expected Decoding, got {other:?}"),
        }
        assert!(matches!(
            UpdateFfiError::from(UpdateError::InvalidResponse),
            UpdateFfiError::InvalidResponse
        ));
    }

    // ── seam: check_update export를 mock FfiReleaseFetcher 주입으로 구동 ───────

    /// canned ReleaseInfoDto/UpdateFfiError를 그대로 돌려주는 테스트용 fetcher.
    struct CannedFetcher(Result<ReleaseInfoDto, UpdateFfiError>);
    impl FfiReleaseFetcher for CannedFetcher {
        fn fetch_latest(&self) -> Result<ReleaseInfoDto, UpdateFfiError> {
            match &self.0 {
                Ok(r) => Ok(release_dto(&r.tag_name)),
                Err(UpdateFfiError::Network { reason }) => Err(UpdateFfiError::Network {
                    reason: reason.clone(),
                }),
                Err(UpdateFfiError::HttpStatus { code }) => {
                    Err(UpdateFfiError::HttpStatus { code: *code })
                }
                Err(UpdateFfiError::Decoding { reason }) => Err(UpdateFfiError::Decoding {
                    reason: reason.clone(),
                }),
                Err(UpdateFfiError::InvalidResponse) => Err(UpdateFfiError::InvalidResponse),
            }
        }
    }

    #[test]
    fn check_update_available_when_release_is_newer() {
        let fetcher: Arc<dyn FfiReleaseFetcher> =
            Arc::new(CannedFetcher(Ok(release_dto("v1.3.0"))));
        match check_update(fetcher, version_dto(1, 2, 0)).expect("expected Ok") {
            UpdateStatusDto::Available { version, url } => {
                assert_eq!((version.major, version.minor, version.patch), (1, 3, 0));
                assert_eq!(url, "https://example/r");
            }
            UpdateStatusDto::UpToDate => panic!("expected Available, got UpToDate"),
        }
    }

    #[test]
    fn check_update_up_to_date_when_not_newer() {
        let fetcher: Arc<dyn FfiReleaseFetcher> = Arc::new(CannedFetcher(Ok(release_dto("1.3.0"))));
        match check_update(fetcher, version_dto(1, 3, 0)).expect("expected Ok") {
            UpdateStatusDto::UpToDate => {}
            UpdateStatusDto::Available { .. } => panic!("expected UpToDate, got Available"),
        }
    }

    #[test]
    fn check_update_error_round_trips_via_err_arm() {
        // fetch 실패 → core UpdateStatus::Error → check_update Err(UpdateFfiError).
        // UpdateFfiError→UpdateError(어댑터)→UpdateStatus::Error→UpdateFfiError 라운드트립.
        let fetcher: Arc<dyn FfiReleaseFetcher> =
            Arc::new(CannedFetcher(Err(UpdateFfiError::HttpStatus { code: 503 })));
        match check_update(fetcher, version_dto(1, 0, 0)) {
            Err(UpdateFfiError::HttpStatus { code }) => assert_eq!(code, 503),
            Err(other) => panic!("expected HttpStatus, got {other:?}"),
            Ok(_) => panic!("expected Err, got Ok"),
        }
    }
}
