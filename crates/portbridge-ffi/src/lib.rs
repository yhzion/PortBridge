use std::time::Duration;
use portbridge_core::model::{PortBridgeError, RemotePort, Server};
use portbridge_core::scan::{scan, CommandError, CommandResult, CommandRunner, DEFAULT_PORT_RANGE};

uniffi::setup_scaffolding!();

#[derive(uniffi::Record)]
pub struct RemotePortDto { pub port: u16, pub address: String, pub process_name: Option<String> }
impl From<RemotePort> for RemotePortDto {
    fn from(p: RemotePort) -> Self { RemotePortDto { port: p.port, address: p.address, process_name: p.process_name } }
}

#[derive(Debug, uniffi::Error)]
pub enum PortBridgeFfiError {
    SshAuthFailed { host: String },
    ServerUnreachable { host: String, reason: String },
    RemoteToolsMissing,
}
impl std::fmt::Display for PortBridgeFfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PortBridgeFfiError::SshAuthFailed { host } => write!(f, "ssh auth failed: {host}"),
            PortBridgeFfiError::ServerUnreachable { host, reason } => write!(f, "server unreachable: {host}: {reason}"),
            PortBridgeFfiError::RemoteToolsMissing => write!(f, "remote tools missing"),
        }
    }
}
impl std::error::Error for PortBridgeFfiError {}
impl From<PortBridgeError> for PortBridgeFfiError {
    fn from(e: PortBridgeError) -> Self {
        match e {
            PortBridgeError::SshAuthFailed { host } => PortBridgeFfiError::SshAuthFailed { host },
            PortBridgeError::ServerUnreachable { host, reason } => PortBridgeFfiError::ServerUnreachable { host, reason },
            PortBridgeError::RemoteToolsMissing => PortBridgeFfiError::RemoteToolsMissing,
        }
    }
}

struct StubRunner { fail: bool }
impl CommandRunner for StubRunner {
    fn run(&self, _e: &str, _a: &[&str], _t: Duration) -> Result<CommandResult, CommandError> {
        if self.fail { return Err(CommandError::TimedOut); }
        Ok(CommandResult { exit_code: 0, stdout: "LISTEN 0 128 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=1,fd=1))\n".to_string(), stderr: String::new() })
    }
}

#[uniffi::export]
pub fn scan_ports(user: String, host: String, port: u16) -> Result<Vec<RemotePortDto>, PortBridgeFfiError> {
    let server = Server { id: format!("{user}@{host}"), name: None, user, host, port };
    let runner = StubRunner { fail: port == 0 };
    let ports = scan(&runner, &server, DEFAULT_PORT_RANGE)?;
    Ok(ports.into_iter().map(RemotePortDto::from).collect())
}
