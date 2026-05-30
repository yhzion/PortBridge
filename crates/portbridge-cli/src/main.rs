//! PortBridge CLI — portbridge-core 위에 구축되는 크로스 플랫폼 진입점.
//!
//! 프로세스 실행·인자 파싱·출력 포매팅만 담당하는 얇은 어댑터.
//! 모든 로직(파싱, 에러 분류, 중복 제거, 필터링)은 core에 위임한다.

use std::io::Read;
use std::ops::RangeInclusive;
use std::process::Command;
use std::time::{Duration, Instant};

use clap::Parser;

use portbridge_core::model::{RemotePort, Server};
use portbridge_core::platform::HostPlatform;
use portbridge_core::scan::{self, CommandError, CommandResult, CommandRunner};
use portbridge_core::ssh_config::{resolve_host, ResolvedHost};

// ── ProcessRunner: std::process::Command 기반 CommandRunner 구현 ──────────

/// `std::process::Command`로 실제 프로세스를 실행하는 어댑터.
///
/// 타임아웃 시 자식을 `Child::kill()`로 회수하고 `wait()`로 좀비를 거둔다.
/// stdout/stderr는 별도 스레드에서 드레인해 파이프 버퍼 포화 데드락을 막는다.
///
/// `kill()`은 직계 자식만 종료한다 — 프로세스 그룹 회수·grace-window는 #41 범위.
struct ProcessRunner;

impl CommandRunner for ProcessRunner {
    fn run(
        &self,
        executable: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<CommandResult, CommandError> {
        let mut child = Command::new(executable)
            .args(args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| CommandError::LaunchFailed(e.to_string()))?;

        // stdout/stderr를 별도 스레드에서 드레인 — 파이프 버퍼 포화 데드락 방지.
        let mut stdout_pipe = child.stdout.take().expect("stdout piped");
        let mut stderr_pipe = child.stderr.take().expect("stderr piped");
        let stdout_handle = std::thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = stdout_pipe.read_to_end(&mut buf);
            buf
        });
        let stderr_handle = std::thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = stderr_pipe.read_to_end(&mut buf);
            buf
        });

        // try_wait 폴링으로 타임아웃을 감지한다.
        let deadline = Instant::now() + timeout;
        let exit_status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {
                    if Instant::now() >= deadline {
                        // 타임아웃: 자식을 kill하고 좀비를 wait로 회수한다.
                        let _ = child.kill();
                        let _ = child.wait();
                        // 파이프가 닫히며 드레인 스레드도 종료된다 — join으로 회수.
                        let _ = stdout_handle.join();
                        let _ = stderr_handle.join();
                        return Err(CommandError::TimedOut);
                    }
                    std::thread::sleep(Duration::from_millis(5));
                }
                Err(e) => return Err(CommandError::LaunchFailed(e.to_string())),
            }
        };

        let stdout = stdout_handle.join().unwrap_or_default();
        let stderr = stderr_handle.join().unwrap_or_default();

        Ok(CommandResult {
            exit_code: exit_status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&stdout).into_owned(),
            stderr: String::from_utf8_lossy(&stderr).into_owned(),
        })
    }
}

// ── CLI 정의 (clap derive) ──────────────────────────────────────────────

/// 원격 서버의 수신 포트를 스캔한다.
#[derive(Parser)]
#[command(name = "portbridge", version, about = "PortBridge CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(clap::Subcommand)]
enum Commands {
    /// 원격 서버의 수신 포트를 스캔한다
    Scan {
        /// SSH 접속 대상: `user@host` 또는 `~/.ssh/config`의 Host alias
        target: String,

        /// SSH 포트 (미지정 시 alias의 config Port, 그것도 없으면 22)
        #[arg(short, long)]
        port: Option<u16>,

        /// 스캔할 포트 범위 (예: 3000-9000). 생략 시 1000-65535
        #[arg(long)]
        range: Option<String>,

        /// 결과를 머신리더블 JSON 배열로 출력 (기본은 사람용 테이블)
        #[arg(long)]
        json: bool,
    },
}

// ── 메인 ────────────────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Scan {
            target,
            port,
            range,
            json,
        } => {
            let server = build_scan_server(&target, port).unwrap_or_else(|msg| {
                eprintln!("error: {msg}");
                std::process::exit(1);
            });

            let port_range = parse_range(range.as_deref()).unwrap_or_else(|msg| {
                eprintln!("error: {msg}");
                std::process::exit(1);
            });

            let runner = ProcessRunner;
            match scan::scan(&runner, &server, port_range) {
                Ok(ports) => {
                    if json {
                        println!("{}", to_json(&ports));
                    } else {
                        print_table(&ports);
                    }
                }
                Err(e) => {
                    eprintln!("{e}");
                    std::process::exit(1);
                }
            }
        }
    }
}

// ── 유틸리티 ────────────────────────────────────────────────────────────

/// 스캔 대상을 `Server`로 해석한다.
///
/// `@` 포함 → `user@host` 직접 입력. bare 토큰 → `~/.ssh/config`의 Host alias로
/// core `resolve_host`를 **소비**해 구성한다(cli는 ssh-config를 직접 파싱하지 않음, §7.3).
fn build_scan_server(target: &str, explicit_port: Option<u16>) -> Result<Server, String> {
    if target.contains('@') {
        let (user, host) =
            split_target(target).ok_or_else(|| "target must be in user@host format".to_string())?;
        Ok(Server {
            id: format!("{user}@{host}"),
            name: None,
            user,
            host,
            port: explicit_port.unwrap_or(22),
        })
    } else {
        match resolve_host(&HostPlatform, target) {
            Ok(Some(resolved)) => server_from_resolved(target, resolved, explicit_port),
            Ok(None) => Err(format!(
                "no Host alias '{target}' in ~/.ssh/config (use user@host)"
            )),
            Err(error) => Err(error.to_string()),
        }
    }
}

/// 해석된 alias로부터 `Server`를 구성한다(순수).
///
/// 포트 우선순위: 명시 `-p` > config `Port` > 22. `HostName` 생략 시 alias를 host로
/// 사용(ssh 관례). `User` 생략 시 `Server.user`를 추측하지 않고 에러로 종료한다.
fn server_from_resolved(
    alias: &str,
    resolved: ResolvedHost,
    explicit_port: Option<u16>,
) -> Result<Server, String> {
    let user = resolved
        .user
        .ok_or_else(|| format!("Host alias '{alias}' has no User (use user@host)"))?;
    let host = resolved.hostname.unwrap_or_else(|| alias.to_string());
    let port = explicit_port.or(resolved.port).unwrap_or(22);
    Ok(Server {
        id: format!("{user}@{host}"),
        name: Some(alias.to_string()),
        user,
        host,
        port,
    })
}

/// `user@host` 문자열을 `(user, host)`로 분리.
fn split_target(target: &str) -> Option<(String, String)> {
    let at = target.find('@')?;
    let user = target[..at].to_string();
    let host = target[at + 1..].to_string();
    if user.is_empty() || host.is_empty() {
        return None;
    }
    Some((user, host))
}

/// `--range` 인자를 `RangeInclusive<u16>`로 파싱. 없으면 기본값 반환.
fn parse_range(range: Option<&str>) -> Result<RangeInclusive<u16>, String> {
    match range {
        None => Ok(scan::DEFAULT_PORT_RANGE),
        Some(s) => {
            let (lo_str, hi_str) = s
                .split_once('-')
                .ok_or_else(|| "range must be in lo-hi format (e.g. 3000-9000)".to_string())?;
            let lo: u16 = lo_str
                .parse()
                .map_err(|_| format!("invalid lower bound: {lo_str}"))?;
            let hi: u16 = hi_str
                .parse()
                .map_err(|_| format!("invalid upper bound: {hi_str}"))?;
            if lo > hi {
                return Err(format!(
                    "lower bound ({lo}) must not exceed upper bound ({hi})"
                ));
            }
            Ok(lo..=hi)
        }
    }
}

/// 결과를 PORT / ADDRESS / PROCESS 테이블로 출력.
fn print_table(ports: &[RemotePort]) {
    println!("{:<8} {:<20} {}", "PORT", "ADDRESS", "PROCESS");
    for rp in ports {
        let process = rp.process_name.as_deref().unwrap_or("-");
        println!("{:<8} {:<20} {}", rp.port, rp.address, process);
    }
}

/// 이미 정렬된 `&[RemotePort]`를 JSON 배열 문자열로 직렬화하는 순수 함수.
///
/// 각 원소는 `{"port":<n>,"address":"<s>","process_name":<"s"|null>}`.
/// 빈 입력은 `[]`을 반환한다(에러 아님). I/O는 호출측 — 포맷 로직만 담당한다.
fn to_json(ports: &[RemotePort]) -> String {
    let mut out = String::from("[");
    for (i, rp) in ports.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str("{\"port\":");
        out.push_str(&rp.port.to_string());
        out.push_str(",\"address\":");
        push_json_string(&mut out, &rp.address);
        out.push_str(",\"process_name\":");
        match &rp.process_name {
            Some(name) => push_json_string(&mut out, name),
            None => out.push_str("null"),
        }
        out.push('}');
    }
    out.push(']');
    out
}

/// 문자열을 JSON 문자열 리터럴(둘러싼 `"` 포함)로 이스케이프해 `out`에 덧붙인다.
fn push_json_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{0008}' => out.push_str("\\b"),
            '\u{000C}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── scan target 해석 (alias → Server) ──────────────────────────────────

    fn resolved(hostname: Option<&str>, user: Option<&str>, port: Option<u16>) -> ResolvedHost {
        ResolvedHost {
            hostname: hostname.map(str::to_string),
            user: user.map(str::to_string),
            port,
            identity_file: None,
        }
    }

    #[test]
    fn resolved_alias_maps_fields_and_uses_config_port() {
        let server = server_from_resolved(
            "prod",
            resolved(Some("10.0.0.1"), Some("ubuntu"), Some(2222)),
            None,
        )
        .unwrap();
        assert_eq!(server.host, "10.0.0.1");
        assert_eq!(server.user, "ubuntu");
        assert_eq!(server.port, 2222);
        assert_eq!(server.name.as_deref(), Some("prod"));
    }

    #[test]
    fn explicit_port_overrides_config_port() {
        let server = server_from_resolved(
            "prod",
            resolved(Some("h"), Some("u"), Some(2222)),
            Some(2022),
        )
        .unwrap();
        assert_eq!(server.port, 2022);
    }

    #[test]
    fn no_config_port_and_no_explicit_defaults_to_22() {
        let server =
            server_from_resolved("prod", resolved(Some("h"), Some("u"), None), None).unwrap();
        assert_eq!(server.port, 22);
    }

    #[test]
    fn omitted_hostname_uses_alias_as_host() {
        let server =
            server_from_resolved("myalias", resolved(None, Some("u"), None), None).unwrap();
        assert_eq!(server.host, "myalias");
    }

    #[test]
    fn omitted_user_is_error() {
        let err = server_from_resolved("prod", resolved(Some("h"), None, None), None).unwrap_err();
        assert!(err.contains("User"));
    }

    #[test]
    fn user_host_target_builds_server_with_default_port() {
        let server = build_scan_server("deploy@10.0.0.1", None).unwrap();
        assert_eq!(server.user, "deploy");
        assert_eq!(server.host, "10.0.0.1");
        assert_eq!(server.port, 22);
        assert_eq!(server.name, None);
    }

    #[test]
    fn user_host_target_uses_explicit_port() {
        let server = build_scan_server("deploy@10.0.0.1", Some(2022)).unwrap();
        assert_eq!(server.port, 2022);
    }

    #[test]
    fn malformed_user_host_target_is_error() {
        assert!(build_scan_server("@host", None).is_err());
    }

    // ── split_target ─────────────────────────────────────────────────────

    #[test]
    fn split_target_parses_user_host() {
        assert_eq!(
            split_target("deploy@10.0.0.1"),
            Some(("deploy".into(), "10.0.0.1".into()))
        );
    }

    #[test]
    fn split_target_allows_at_in_host() {
        assert_eq!(
            split_target("user@host@example.com"),
            Some(("user".into(), "host@example.com".into()))
        );
    }

    #[test]
    fn split_target_rejects_no_at() {
        assert_eq!(split_target("no-at-sign"), None);
    }

    #[test]
    fn split_target_rejects_empty_user() {
        assert_eq!(split_target("@host"), None);
    }

    #[test]
    fn split_target_rejects_empty_host() {
        assert_eq!(split_target("user@"), None);
    }

    #[test]
    fn split_target_rejects_empty_string() {
        assert_eq!(split_target(""), None);
    }

    // ── parse_range ──────────────────────────────────────────────────────

    #[test]
    fn parse_range_none_returns_default() {
        assert_eq!(parse_range(None), Ok(scan::DEFAULT_PORT_RANGE));
    }

    #[test]
    fn parse_range_valid_range() {
        assert_eq!(parse_range(Some("3000-9000")), Ok(3000..=9000));
    }

    #[test]
    fn parse_range_single_value_missing_dash() {
        assert!(parse_range(Some("3000")).is_err());
    }

    #[test]
    fn parse_range_reversed_bounds() {
        let err = parse_range(Some("9000-3000")).unwrap_err();
        assert!(err.contains("must not exceed"));
    }

    #[test]
    fn parse_range_non_numeric() {
        assert!(parse_range(Some("abc-def")).is_err());
    }

    #[test]
    fn parse_range_empty_string() {
        assert!(parse_range(Some("")).is_err());
    }

    #[test]
    fn parse_range_equal_bounds() {
        assert_eq!(parse_range(Some("8080-8080")), Ok(8080..=8080));
    }

    // ── to_json ──────────────────────────────────────────────────────────

    /// 세 필드를 가진 객체의 JSON 배열로 직렬화한다 (객체 구조 고정).
    #[test]
    fn to_json_serializes_port_fields() {
        let ports = vec![RemotePort {
            port: 8080,
            address: "127.0.0.1".into(),
            process_name: Some("nginx".into()),
        }];
        assert_eq!(
            to_json(&ports),
            r#"[{"port":8080,"address":"127.0.0.1","process_name":"nginx"}]"#
        );
    }

    /// process_name이 None이면 JSON null로 매핑한다.
    #[test]
    fn to_json_maps_none_process_to_null() {
        let ports = vec![RemotePort {
            port: 22,
            address: "0.0.0.0".into(),
            process_name: None,
        }];
        assert_eq!(
            to_json(&ports),
            r#"[{"port":22,"address":"0.0.0.0","process_name":null}]"#
        );
    }

    /// 빈 입력은 빈 배열 `[]` (에러 아님).
    #[test]
    fn to_json_empty_input_is_empty_array() {
        assert_eq!(to_json(&[]), "[]");
    }

    /// 문자열의 `"`와 `\`를 올바르게 이스케이프한다.
    #[test]
    fn to_json_escapes_quote_and_backslash() {
        let ports = vec![RemotePort {
            port: 1,
            address: "a\"b".into(),
            process_name: Some("c\\d".into()),
        }];
        assert_eq!(
            to_json(&ports),
            r#"[{"port":1,"address":"a\"b","process_name":"c\\d"}]"#
        );
    }

    // ── ProcessRunner ────────────────────────────────────────────────────

    /// 타임아웃 시 자식 프로세스를 회수(kill)하는지 검증.
    ///
    /// 자식이 살아남으면 1초 뒤 marker 파일을 touch한다. 짧은 타임아웃 후
    /// 충분히 기다려도 marker가 없으면 자식이 종료된 것이다.
    /// `sleep` 의존이라 unix 한정.
    #[cfg(unix)]
    #[test]
    fn run_kills_child_on_timeout() {
        let marker =
            std::env::temp_dir().join(format!("pb_kill_test_{}.marker", std::process::id()));
        let _ = std::fs::remove_file(&marker);

        let script = format!("sleep 1; touch '{}'", marker.display());
        let result = ProcessRunner.run("sh", &["-c", &script], Duration::from_millis(100));

        assert!(
            matches!(result, Err(CommandError::TimedOut)),
            "타임아웃은 TimedOut을 반환해야 한다: {result:?}"
        );

        // 자식이 살아있었다면 ~1초 후 touch한다. 넉넉히 기다린다.
        std::thread::sleep(Duration::from_millis(1500));
        let child_survived = marker.exists();
        let _ = std::fs::remove_file(&marker);

        assert!(
            !child_survived,
            "타임아웃된 자식이 종료되지 않고 marker를 생성했다 (kill 누락)"
        );
    }

    /// 정상 종료한 명령의 stdout과 exit_code를 회수한다.
    #[cfg(unix)]
    #[test]
    fn run_returns_output_for_completed_command() {
        let result = ProcessRunner
            .run("sh", &["-c", "echo hello"], Duration::from_secs(5))
            .expect("정상 명령은 결과를 반환해야 한다");
        assert_eq!(result.stdout.trim(), "hello");
        assert_eq!(result.exit_code, 0);
    }

    /// 비영(非0) 종료 코드를 보존한다.
    #[cfg(unix)]
    #[test]
    fn run_preserves_nonzero_exit_code() {
        let result = ProcessRunner
            .run("sh", &["-c", "exit 3"], Duration::from_secs(5))
            .expect("결과를 반환해야 한다");
        assert_eq!(result.exit_code, 3);
    }

    /// 파이프 버퍼(64KB)를 초과하는 출력도 드레인 스레드 덕에 데드락 없이 회수한다.
    /// 드레인을 빠뜨리면 자식이 write에서 블록 → 타임아웃으로 실패한다.
    #[cfg(unix)]
    #[test]
    fn run_drains_large_output_without_deadlock() {
        let result = ProcessRunner
            .run(
                "sh",
                &["-c", "yes pb | head -n 100000"],
                Duration::from_secs(10),
            )
            .expect("대용량 출력도 회수해야 한다");
        assert_eq!(result.stdout.lines().count(), 100000);
    }
}
