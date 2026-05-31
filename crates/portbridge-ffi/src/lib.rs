use portbridge_core::model::{PortBridgeError, RemotePort, Server};
use portbridge_core::platform::Platform;
use portbridge_core::scan::{scan, CommandError, CommandResult, CommandRunner, DEFAULT_PORT_RANGE};
use portbridge_core::ssh_config::{resolve_host as core_resolve_host, ResolvedHost};
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
}
