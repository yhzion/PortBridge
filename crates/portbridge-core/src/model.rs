use std::{error::Error, fmt};

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

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PortBridgeError {
    SshAuthFailed { host: String },
    ServerUnreachable { host: String, reason: String },
    RemoteToolsMissing,
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
}
