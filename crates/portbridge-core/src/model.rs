use std::{error::Error, fmt, time::SystemTime};

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct Server {
    pub id: String,
    pub name: Option<String>,
    pub user: String,
    pub host: String,
    pub port: u16,
}

impl Server {
    pub fn ssh_target(&self) -> String {
        format!("{}@{}", self.user, self.host)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct RemotePort {
    pub port: u16,
    pub address: String,
    pub process_name: Option<String>,
}

/// 터널(포워딩) 수명주기 상태. Swift `Forwarding.State` 매핑.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum State {
    Idle,
    Starting,
    Active,
    Error(String),
}

/// 로컬↔원격 포트 매핑(터널) 도메인 타입. Swift `Forwarding` 매핑.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Forwarding {
    pub id: String,
    pub server_id: String,
    pub remote_port: u16,
    pub local_port: u16,
    pub state: State,
    pub activated_at: Option<SystemTime>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PortBridgeError {
    SshAuthFailed { host: String },
    ServerUnreachable { host: String, reason: String },
    RemoteToolsMissing,
    ForwardingDiedEarly { stderr: String },
    SshConfigNotFound,
    SshConfigUnreadable { reason: String },
}

impl fmt::Display for PortBridgeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SshAuthFailed { host } => {
                write!(f, "{host} SSH authentication failed")
            }
            Self::ServerUnreachable { host, .. } => {
                write!(f, "{host} server is unreachable")
            }
            Self::RemoteToolsMissing => {
                write!(f, "remote server requires ss or lsof")
            }
            Self::ForwardingDiedEarly { stderr } => {
                write!(f, "forwarding died early: {stderr}")
            }
            Self::SshConfigNotFound => {
                write!(f, "~/.ssh/config not found")
            }
            Self::SshConfigUnreadable { reason } => {
                write!(f, "~/.ssh/config unreadable: {reason}")
            }
        }
    }
}

impl Error for PortBridgeError {}

#[cfg(test)]
mod tests {
    use super::*;

    fn server(name: Option<&str>) -> Server {
        Server {
            id: "server-1".to_string(),
            name: name.map(str::to_string),
            user: "deploy".to_string(),
            host: "10.0.0.1".to_string(),
            port: 2222,
        }
    }

    #[test]
    fn server_ssh_target_combines_user_and_host() {
        assert_eq!(server(None).ssh_target(), "deploy@10.0.0.1");
    }

    #[test]
    fn remote_port_carries_port_address_and_process_name() {
        let port = RemotePort {
            port: 5432,
            address: "127.0.0.1".to_string(),
            process_name: Some("postgres".to_string()),
        };

        assert_eq!(port.port, 5432);
        assert_eq!(port.address, "127.0.0.1");
        assert_eq!(port.process_name.as_deref(), Some("postgres"));
    }

    #[test]
    fn port_bridge_error_display_covers_scan_errors() {
        assert_eq!(
            PortBridgeError::SshAuthFailed {
                host: "prod".to_string(),
            }
            .to_string(),
            "prod SSH authentication failed"
        );
        assert_eq!(
            PortBridgeError::ServerUnreachable {
                host: "prod".to_string(),
                reason: "no route to host".to_string(),
            }
            .to_string(),
            "prod server is unreachable"
        );
        assert_eq!(
            PortBridgeError::RemoteToolsMissing.to_string(),
            "remote server requires ss or lsof"
        );
    }

    // ── 터널 도메인: State ────────────────────────────────────────────────

    #[test]
    fn state_distinguishes_active_from_error() {
        assert_ne!(State::Active, State::Error("boom".to_string()));
    }

    #[test]
    fn state_error_preserves_reason() {
        match State::Error("connection refused".to_string()) {
            State::Error(reason) => assert_eq!(reason, "connection refused"),
            other => panic!("expected Error variant, got {other:?}"),
        }
    }

    // ── 터널 도메인: Forwarding ───────────────────────────────────────────

    #[test]
    fn forwarding_preserves_all_fields() {
        let activated = std::time::SystemTime::UNIX_EPOCH;
        let forwarding = Forwarding {
            id: "fwd-1".to_string(),
            server_id: "server-1".to_string(),
            remote_port: 5432,
            local_port: 15432,
            state: State::Active,
            activated_at: Some(activated),
        };

        assert_eq!(forwarding.id, "fwd-1");
        assert_eq!(forwarding.server_id, "server-1");
        assert_eq!(forwarding.remote_port, 5432);
        assert_eq!(forwarding.local_port, 15432);
        assert_eq!(forwarding.state, State::Active);
        assert_eq!(forwarding.activated_at, Some(activated));
    }

    #[test]
    fn port_bridge_error_display_covers_forwarding_died_early() {
        assert_eq!(
            PortBridgeError::ForwardingDiedEarly {
                stderr: "bind: address already in use".to_string(),
            }
            .to_string(),
            "forwarding died early: bind: address already in use"
        );
    }

    #[test]
    fn port_bridge_error_display_covers_ssh_config_errors() {
        assert_eq!(
            PortBridgeError::SshConfigNotFound.to_string(),
            "~/.ssh/config not found"
        );
        assert_eq!(
            PortBridgeError::SshConfigUnreadable {
                reason: "permission denied".to_string(),
            }
            .to_string(),
            "~/.ssh/config unreadable: permission denied"
        );
    }
}
