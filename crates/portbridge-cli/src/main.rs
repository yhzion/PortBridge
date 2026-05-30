//! PortBridge CLI — portbridge-core 위에 구축되는 크로스 플랫폼 진입점.
//!
//! 프로세스 실행·인자 파싱·출력 포매팅만 담당하는 얇은 어댑터.
//! 모든 로직(파싱, 에러 분류, 중복 제거, 필터링)은 core에 위임한다.

use std::ops::RangeInclusive;
use std::process::Command;
use std::sync::mpsc;
use std::time::Duration;

use clap::Parser;

use portbridge_core::model::{RemotePort, Server};
use portbridge_core::scan::{self, CommandError, CommandResult, CommandRunner};

// ── ProcessRunner: std::process::Command 기반 CommandRunner 구현 ──────────

/// `std::process::Command`로 실제 프로세스를 실행하는 어댑터.
struct ProcessRunner;

impl CommandRunner for ProcessRunner {
    fn run(
        &self,
        executable: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<CommandResult, CommandError> {
        let (tx, rx) = mpsc::channel();

        let exec = executable.to_string();
        let args: Vec<String> = args.iter().map(|s| (*s).to_string()).collect();

        std::thread::spawn(move || {
            let result = Command::new(&exec)
                .args(&args)
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .output();
            let _ = tx.send(result);
        });

        match rx.recv_timeout(timeout) {
            Ok(output_result) => {
                let output =
                    output_result.map_err(|e| CommandError::LaunchFailed(e.to_string()))?;
                Ok(CommandResult {
                    exit_code: output.status.code().unwrap_or(-1),
                    stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
                    stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
                })
            }
            Err(_) => Err(CommandError::TimedOut),
        }
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
        /// SSH 접속 대상 (user@host)
        target: String,

        /// SSH 포트
        #[arg(short, long, default_value_t = 22)]
        port: u16,

        /// 스캔할 포트 범위 (예: 3000-9000). 생략 시 1000-65535
        #[arg(long)]
        range: Option<String>,
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
        } => {
            let (user, host) = split_target(&target).unwrap_or_else(|| {
                eprintln!("error: target must be in user@host format");
                std::process::exit(1);
            });

            let port_range = parse_range(range.as_deref()).unwrap_or_else(|msg| {
                eprintln!("error: {msg}");
                std::process::exit(1);
            });

            let server = Server {
                id: format!("{user}@{host}"),
                name: None,
                user,
                host,
                port,
            };

            let runner = ProcessRunner;
            match scan::scan(&runner, &server, port_range) {
                Ok(ports) => print_table(&ports),
                Err(e) => {
                    eprintln!("{e}");
                    std::process::exit(1);
                }
            }
        }
    }
}

// ── 유틸리티 ────────────────────────────────────────────────────────────

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
