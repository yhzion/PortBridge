use std::{collections::BTreeMap, error::Error, fmt, ops::RangeInclusive, time::Duration};

use crate::model::{PortBridgeError, RemotePort, Server};

const SSH_EXECUTABLE: &str = "/usr/bin/ssh";
const SSH_TIMEOUT: Duration = Duration::from_secs(15);
const REMOTE_SCAN_COMMAND: &str = r#"if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
  echo PORTBRIDGE_TOOLS_MISSING >&2
  exit 127
fi
ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"#;

pub const DEFAULT_PORT_RANGE: RangeInclusive<u16> = 1000..=65535;

pub trait CommandRunner {
    fn run(
        &self,
        executable: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<CommandResult, CommandError>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CommandError {
    TimedOut,
    LaunchFailed(String),
}

impl fmt::Display for CommandError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TimedOut => write!(f, "command timed out"),
            Self::LaunchFailed(reason) => write!(f, "command launch failed: {reason}"),
        }
    }
}

impl Error for CommandError {}

pub fn parse_ss(output: &str) -> Vec<RemotePort> {
    output.lines().filter_map(parse_ss_line).collect()
}

pub fn parse_lsof(output: &str) -> Vec<RemotePort> {
    output
        .lines()
        .enumerate()
        .filter_map(|(index, raw)| parse_lsof_line(index, raw))
        .collect()
}

pub fn scan<R: CommandRunner + ?Sized>(
    runner: &R,
    server: &Server,
    range: RangeInclusive<u16>,
) -> Result<Vec<RemotePort>, PortBridgeError> {
    let port = server.port.to_string();
    let target = server.ssh_target();
    let args = [
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=10",
        "-p",
        port.as_str(),
        target.as_str(),
        REMOTE_SCAN_COMMAND,
    ];

    let result = runner
        .run(SSH_EXECUTABLE, &args, SSH_TIMEOUT)
        .map_err(|error| classify_command_error(error, server))?;

    if result.exit_code != 0 {
        return Err(classify_exit_error(&result, server));
    }

    let parsed = if looks_like_ss(&result.stdout) {
        parse_ss(&result.stdout)
    } else {
        parse_lsof(&result.stdout)
    };

    let mut ports: Vec<_> = deduplicate_same_port(parsed)
        .into_iter()
        .filter(|port| range.contains(&port.port))
        .collect();
    ports.sort_by_key(|port| port.port);
    Ok(ports)
}

fn parse_ss_line(raw: &str) -> Option<RemotePort> {
    let line = raw.trim();
    if line.is_empty() {
        return None;
    }

    let first_word = line.split_whitespace().next()?;
    if !first_word.eq_ignore_ascii_case("LISTEN") {
        return None;
    }

    let columns: Vec<_> = line.split_whitespace().collect();
    let local_address = *columns.get(3)?;
    let (address, port) = split_address_port(local_address)?;
    let process_name = extract_process_name(line);

    Some(RemotePort {
        port,
        address,
        process_name,
    })
}

fn parse_lsof_line(index: usize, raw: &str) -> Option<RemotePort> {
    let line = raw.trim();
    if line.is_empty() {
        return None;
    }
    if index == 0 && line.to_ascii_uppercase().starts_with("COMMAND") {
        return None;
    }
    if !line.contains("(LISTEN)") {
        return None;
    }

    let columns: Vec<_> = line.split_whitespace().collect();
    if columns.len() < 9 {
        return None;
    }

    let command = columns[0];
    let name = columns[columns.len() - 2].replace('*', "0.0.0.0");
    let (address, port) = split_address_port(&name)?;
    let process_name = (command != "-").then(|| command.to_string());

    Some(RemotePort {
        port,
        address,
        process_name,
    })
}

fn split_address_port(input: &str) -> Option<(String, u16)> {
    if let Some(rest) = input.strip_prefix('[') {
        let close = rest.find(']')?;
        let address = &rest[..close];
        let after_close = &rest[close + 1..];
        let port = after_close.strip_prefix(':')?.parse().ok()?;
        return Some((address.to_string(), port));
    }

    let colon = input.rfind(':')?;
    let address = &input[..colon];
    let port = input[colon + 1..].parse().ok()?;
    Some((address.to_string(), port))
}

fn extract_process_name(line: &str) -> Option<String> {
    const PREFIX: &str = "users:((\"";
    let users_start = line.find(PREFIX)?;
    let rest = &line[users_start + PREFIX.len()..];
    let quote_end = rest.find('"')?;
    let name = &rest[..quote_end];
    (!name.is_empty()).then(|| name.to_string())
}

fn classify_command_error(error: CommandError, server: &Server) -> PortBridgeError {
    let reason = match error {
        CommandError::TimedOut => "command timed out".to_string(),
        CommandError::LaunchFailed(reason) => reason,
    };

    PortBridgeError::ServerUnreachable {
        host: server.host.clone(),
        reason,
    }
}

fn classify_exit_error(result: &CommandResult, server: &Server) -> PortBridgeError {
    let stderr = result.stderr.to_ascii_lowercase();

    if stderr.contains("permission denied") || stderr.contains("publickey") {
        return PortBridgeError::SshAuthFailed {
            host: server.host.clone(),
        };
    }

    let unreachable_patterns = [
        "connection timed out",
        "connect timeout",
        "operation timed out",
        "no route to host",
        "connection refused",
        "could not resolve hostname",
        "name or service not known",
        "network is unreachable",
        "host is down",
    ];
    if unreachable_patterns
        .iter()
        .any(|pattern| stderr.contains(pattern))
    {
        return PortBridgeError::ServerUnreachable {
            host: server.host.clone(),
            reason: result.stderr.clone(),
        };
    }

    if result.exit_code == 127 || stderr.contains("portbridge_tools_missing") {
        return PortBridgeError::RemoteToolsMissing;
    }

    PortBridgeError::ServerUnreachable {
        host: server.host.clone(),
        reason: result.stderr.clone(),
    }
}

fn looks_like_ss(stdout: &str) -> bool {
    let first = stdout
        .lines()
        .find(|line| !line.trim().is_empty())
        .unwrap_or_default();
    first
        .split_whitespace()
        .next()
        .is_some_and(|word| word.eq_ignore_ascii_case("LISTEN"))
        || first.contains("State")
}

fn deduplicate_same_port(ports: Vec<RemotePort>) -> Vec<RemotePort> {
    let mut grouped: BTreeMap<u16, Vec<RemotePort>> = BTreeMap::new();
    for port in ports {
        grouped.entry(port.port).or_default().push(port);
    }

    grouped
        .into_iter()
        .map(|(port, matches)| RemotePort {
            port,
            address: representative_address(&matches),
            process_name: matches
                .iter()
                .find_map(|port| port.process_name.as_ref().filter(|name| !name.is_empty()))
                .cloned(),
        })
        .collect()
}

fn representative_address(ports: &[RemotePort]) -> String {
    let has_address = |needle: &str| ports.iter().any(|port| port.address == needle);

    if has_address("0.0.0.0") || has_address("::") {
        return "0.0.0.0".to_string();
    }
    if has_address("127.0.0.1") {
        return "127.0.0.1".to_string();
    }
    if has_address("::1") {
        return "::1".to_string();
    }

    ports
        .iter()
        .map(|port| port.address.as_str())
        .min()
        .unwrap_or_default()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct MockRunner {
        result: Option<Result<CommandResult, CommandError>>,
        calls: std::cell::RefCell<Vec<Call>>,
    }

    #[derive(Debug, Eq, PartialEq)]
    struct Call {
        executable: String,
        args: Vec<String>,
        timeout: Duration,
    }

    impl MockRunner {
        fn with_result(result: CommandResult) -> Self {
            Self {
                result: Some(Ok(result)),
                calls: std::cell::RefCell::new(Vec::new()),
            }
        }

        fn with_error(error: CommandError) -> Self {
            Self {
                result: Some(Err(error)),
                calls: std::cell::RefCell::new(Vec::new()),
            }
        }
    }

    impl CommandRunner for MockRunner {
        fn run(
            &self,
            executable: &str,
            args: &[&str],
            timeout: Duration,
        ) -> Result<CommandResult, CommandError> {
            self.calls.borrow_mut().push(Call {
                executable: executable.to_string(),
                args: args.iter().map(|arg| (*arg).to_string()).collect(),
                timeout,
            });
            self.result.as_ref().expect("mock result missing").clone()
        }
    }

    fn server() -> Server {
        Server {
            id: "server-1".to_string(),
            name: None,
            user: "ubuntu".to_string(),
            host: "prod".to_string(),
            port: 22,
        }
    }

    fn command_result(exit_code: i32, stdout: &str, stderr: &str) -> CommandResult {
        CommandResult {
            exit_code,
            stdout: stdout.to_string(),
            stderr: stderr.to_string(),
        }
    }

    #[test]
    fn default_port_range_matches_swift_scan_default() {
        assert!(DEFAULT_PORT_RANGE.contains(&1000));
        assert!(DEFAULT_PORT_RANGE.contains(&65535));
        assert!(!DEFAULT_PORT_RANGE.contains(&999));
    }

    #[test]
    fn parse_ss_no_header_extracts_listening_ports() {
        let output = "\
LISTEN 0 128 0.0.0.0:22 0.0.0.0:*
LISTEN 0 100 127.0.0.1:5432 0.0.0.0:*
LISTEN 0 128 [::]:80 [::]:*
LISTEN 0 50 127.0.0.1:8080 0.0.0.0:*
";

        let ports = parse_ss(output);

        assert_eq!(ports.len(), 4);
        assert!(ports
            .iter()
            .any(|port| port.port == 22 && port.address == "0.0.0.0"));
        assert!(ports
            .iter()
            .any(|port| port.port == 5432 && port.address == "127.0.0.1"));
        assert!(ports
            .iter()
            .any(|port| port.port == 80 && port.address == "::"));
    }

    #[test]
    fn parse_ss_with_header_skips_header_line() {
        let output = "\
State Recv-Q Send-Q Local Address:Port Peer Address:Port
LISTEN 0 128 0.0.0.0:22 0.0.0.0:*
LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*
";

        assert_eq!(parse_ss(output).len(), 2);
    }

    #[test]
    fn parse_ss_ipv6_mixed_handles_brackets_and_process_name() {
        let output = "\
State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0 128 [::]:22 [::]:* users:((\"sshd\",pid=1,fd=3))
LISTEN 0 100 [::1]:5432 [::]:*
LISTEN 0 128 0.0.0.0:443 0.0.0.0:*
";

        let ports = parse_ss(output);

        assert_eq!(ports.len(), 3);
        assert!(ports
            .iter()
            .any(|port| port.port == 22 && port.address == "::"));
        assert!(ports
            .iter()
            .any(|port| port.port == 5432 && port.address == "::1"));
        assert_eq!(
            ports
                .iter()
                .find(|port| port.port == 22)
                .and_then(|port| port.process_name.as_deref()),
            Some("sshd")
        );
    }

    #[test]
    fn parse_lsof_typical_extracts_ports_and_processes() {
        let output = "\
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
sshd     1   root   3u   IPv4  12345      0t0  TCP *:22 (LISTEN)
postgres 100 postgres 5u IPv4  23456      0t0  TCP 127.0.0.1:5432 (LISTEN)
nginx    200 www-data 6u IPv6  34567      0t0  TCP [::]:80 (LISTEN)
";

        let ports = parse_lsof(output);

        assert_eq!(ports.len(), 3);
        assert!(ports.iter().any(|port| port.port == 22
            && port.address == "0.0.0.0"
            && port.process_name.as_deref() == Some("sshd")));
        assert!(ports.iter().any(|port| port.port == 5432
            && port.address == "127.0.0.1"
            && port.process_name.as_deref() == Some("postgres")));
    }

    #[test]
    fn parse_lsof_accepts_omitted_size_offset_column() {
        let output = "\
COMMAND  PID USER   FD   TYPE DEVICE NODE NAME
postgres 100 postgres 5u IPv4  23456  TCP 127.0.0.1:5432 (LISTEN)
";

        let ports = parse_lsof(output);

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 5432);
        assert_eq!(ports[0].address, "127.0.0.1");
        assert_eq!(ports[0].process_name.as_deref(), Some("postgres"));
    }

    #[test]
    fn parse_lsof_dash_process_becomes_none() {
        let output = "\
COMMAND  PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
-        -   -    3u IPv4 0      0t0      TCP 0.0.0.0:3000 (LISTEN)
";

        let ports = parse_lsof(output);

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 3000);
        assert_eq!(ports[0].process_name, None);
    }

    #[test]
    fn scan_success_returns_parsed_ports() {
        let runner = MockRunner::with_result(command_result(
            0,
            "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*\nLISTEN 0 100 127.0.0.1:5432 0.0.0.0:*",
            "",
        ));

        let ports = scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed");

        assert_eq!(ports.len(), 2);
        assert!(ports.iter().any(|port| port.port == 3000));
        assert!(ports.iter().any(|port| port.port == 5432));
    }

    #[test]
    fn scan_lsof_success_returns_parsed_ports() {
        let runner = MockRunner::with_result(command_result(
            0,
            "\
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
sshd     1   root   3u   IPv4  12345      0t0  TCP *:22 (LISTEN)
postgres 100 postgres 5u IPv4  23456      0t0  TCP 127.0.0.1:5432 (LISTEN)
",
            "",
        ));

        let ports = scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed");

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 5432);
        assert_eq!(ports[0].address, "127.0.0.1");
        assert_eq!(ports[0].process_name.as_deref(), Some("postgres"));
    }

    #[test]
    fn scan_filters_out_of_range_ports() {
        let runner = MockRunner::with_result(command_result(
            0,
            "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:3000 0.0.0.0:*",
            "",
        ));

        let ports = scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed");

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 3000);
    }

    #[test]
    fn scan_deduplicates_ipv4_and_ipv6_wildcard_for_same_port() {
        let runner = MockRunner::with_result(command_result(
            0,
            "\
LISTEN 0 4096 0.0.0.0:8000 0.0.0.0:* users:((\"vllm\",pid=1,fd=3))
LISTEN 0 4096 [::]:8000 [::]:* users:((\"vllm\",pid=1,fd=4))
",
            "",
        ));

        let ports = scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed");

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].port, 8000);
        assert_eq!(ports[0].address, "0.0.0.0");
        assert_eq!(ports[0].process_name.as_deref(), Some("vllm"));
    }

    #[test]
    fn scan_deduplicates_loopback_for_same_port() {
        let runner = MockRunner::with_result(command_result(
            0,
            "\
LISTEN 0 4096 127.0.0.1:8000 0.0.0.0:*
LISTEN 0 4096 [::1]:8000 [::]:*
",
            "",
        ));

        let ports = scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed");

        assert_eq!(ports.len(), 1);
        assert_eq!(ports[0].address, "127.0.0.1");
    }

    #[test]
    fn scan_uses_sync_runner_with_expected_ssh_args() {
        let custom_server = Server {
            id: "server-1".to_string(),
            name: None,
            user: "deploy".to_string(),
            host: "10.0.0.1".to_string(),
            port: 2222,
        };
        let runner = MockRunner::with_result(command_result(0, "", ""));

        let _ = scan(&runner, &custom_server, DEFAULT_PORT_RANGE).expect("scan should succeed");

        let calls = runner.calls.borrow();
        let call = calls.first().expect("runner should be called");
        assert_eq!(call.executable, "/usr/bin/ssh");
        assert_eq!(call.timeout, Duration::from_secs(15));
        assert!(call.args.iter().any(|arg| arg == "-p"));
        assert!(call.args.iter().any(|arg| arg == "2222"));
        assert!(call.args.iter().any(|arg| arg == "deploy@10.0.0.1"));
        assert!(call
            .args
            .iter()
            .any(|arg| arg.contains("PORTBRIDGE_TOOLS_MISSING")));
    }

    #[test]
    fn scan_auth_failed_stderr_throws_auth_error() {
        let runner =
            MockRunner::with_result(command_result(255, "", "Permission denied (publickey)."));

        assert_eq!(
            scan(&runner, &server(), DEFAULT_PORT_RANGE),
            Err(PortBridgeError::SshAuthFailed {
                host: "prod".to_string(),
            })
        );
    }

    #[test]
    fn scan_unreachable_stderr_patterns_throw_server_unreachable() {
        let patterns = [
            "Connection timed out",
            "No route to host",
            "Connection refused",
            "Could not resolve hostname prod: Name or service not known",
            "Network is unreachable",
            "Host is down",
            "Operation timed out",
        ];

        for stderr in patterns {
            let runner = MockRunner::with_result(command_result(255, "", stderr));
            assert!(matches!(
                scan(&runner, &server(), DEFAULT_PORT_RANGE),
                Err(PortBridgeError::ServerUnreachable { host, .. }) if host == "prod"
            ));
        }
    }

    #[test]
    fn scan_tools_missing_marker_or_exit_127_throws_remote_tools_missing() {
        for result in [
            command_result(127, "", "PORTBRIDGE_TOOLS_MISSING\n"),
            command_result(127, "", ""),
        ] {
            let runner = MockRunner::with_result(result);
            assert_eq!(
                scan(&runner, &server(), DEFAULT_PORT_RANGE),
                Err(PortBridgeError::RemoteToolsMissing)
            );
        }
    }

    #[test]
    fn scan_empty_stdout_without_error_signal_returns_empty_array() {
        let runner = MockRunner::with_result(command_result(0, "", ""));

        assert_eq!(
            scan(&runner, &server(), DEFAULT_PORT_RANGE).expect("scan should succeed"),
            Vec::<RemotePort>::new()
        );
    }

    #[test]
    fn scan_command_errors_are_classified_as_unreachable() {
        for error in [
            CommandError::TimedOut,
            CommandError::LaunchFailed("no result".to_string()),
        ] {
            let runner = MockRunner::with_error(error);
            assert!(matches!(
                scan(&runner, &server(), DEFAULT_PORT_RANGE),
                Err(PortBridgeError::ServerUnreachable { host, .. }) if host == "prod"
            ));
        }
    }
}
