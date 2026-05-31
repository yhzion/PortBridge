//! PortBridge CLI — portbridge-core 위에 구축되는 크로스 플랫폼 진입점.
//!
//! 프로세스 실행·인자 파싱·출력 포매팅만 담당하는 얇은 어댑터.
//! 모든 로직(파싱, 에러 분류, 중복 제거, 필터링)은 core에 위임한다.

use std::io::Read;
use std::ops::RangeInclusive;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant, SystemTime};

use clap::Parser;

use portbridge_core::model::{PortBridgeError, RemotePort, Server};
use portbridge_core::persistence::Persistence;
use portbridge_core::platform::HostPlatform;
use portbridge_core::scan::{self, CommandError, CommandResult, CommandRunner};
use portbridge_core::ssh_config::{resolve_host, ResolvedHost};
use portbridge_core::tunnel::{self, ForwardSpec, TunnelProcess, TunnelSpawner};

mod store;

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
    /// 저장된 서버를 관리한다 (영속 저장: add/ls/rm/show)
    Server {
        #[command(subcommand)]
        action: ServerCmd,
    },

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

    /// SSH 로컬 포트 포워딩(`ssh -L`)을 실행한다 (foreground; Ctrl-C로 종료)
    Tunnel {
        /// SSH 접속 대상: `user@host`, 저장 서버 이름/id, 또는 `~/.ssh/config` Host alias
        target: String,

        /// 포워딩 스펙: `<local_port>:<remote_host>:<remote_port>`
        #[arg(short = 'L')]
        forward: String,

        /// SSH 포트 (미지정 시 저장 서버/alias의 Port, 그것도 없으면 22)
        #[arg(short, long)]
        port: Option<u16>,
    },
}

// ── 메인 ────────────────────────────────────────────────────────────────

// ── server 서브커맨드 ────────────────────────────────────────────────────

#[derive(clap::Subcommand)]
enum ServerCmd {
    /// 서버를 저장한다
    Add {
        /// SSH 접속 대상 (user@host)
        target: String,
        /// 표시 이름 (선택)
        #[arg(long)]
        name: Option<String>,
        /// SSH 포트
        #[arg(short, long, default_value_t = 22)]
        port: u16,
    },
    /// 저장된 서버 목록
    Ls {
        /// 머신리더블 JSON으로 출력
        #[arg(long)]
        json: bool,
    },
    /// 서버 삭제 (id 또는 name)
    Rm { ident: String },
    /// 서버 상세 (id 또는 name)
    Show { ident: String },
}

/// `server` 서브커맨드 디스패치 — 파일 저장소를 열고 액션을 실행한다(I/O 경계).
fn run_server(action: ServerCmd) {
    let store = store::FileStore::new(store::config_dir());
    let result = match action {
        ServerCmd::Add { target, name, port } => server_add(&store, &target, name, port),
        ServerCmd::Ls { json } => server_ls(&store, json),
        ServerCmd::Rm { ident } => server_rm(&store, &ident),
        ServerCmd::Show { ident } => server_show(&store, &ident),
    };
    if let Err(msg) = result {
        eprintln!("error: {msg}");
        std::process::exit(1);
    }
}

/// 서버 식별자(CLI 내부 생성). 단일 사용자 환경에서 충분히 유일.
fn new_server_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("srv-{nanos:x}")
}

/// 서버를 저장한다. `(user,host,port)` 중복은 거부(Desktop `isDuplicate` 동치).
fn server_add(
    p: &dyn Persistence,
    target: &str,
    name: Option<String>,
    port: u16,
) -> Result<(), String> {
    let (user, host) =
        split_target(target).ok_or_else(|| "target must be in user@host format".to_string())?;
    let mut servers = store::load_servers(p)?;
    if store::is_duplicate(&servers, &user, &host, port) {
        return Err(format!("이미 저장된 서버: {user}@{host}:{port}"));
    }
    let id = new_server_id();
    servers.push(Server {
        id: id.clone(),
        name,
        user: user.clone(),
        host: host.clone(),
        port,
    });
    store::save_servers(p, &servers)?;
    println!("저장됨: {id}  {user}@{host}:{port}");
    Ok(())
}

/// 저장된 서버 목록을 테이블/JSON으로 출력한다.
fn server_ls(p: &dyn Persistence, json: bool) -> Result<(), String> {
    let servers = store::load_servers(p)?;
    if json {
        println!(
            "{}",
            serde_json::to_string(&servers).map_err(|e| e.to_string())?
        );
    } else {
        println!("{}", format_server_table(&servers));
    }
    Ok(())
}

/// id 또는 name으로 서버를 삭제한다. 일치 항목이 없으면 에러.
fn server_rm(p: &dyn Persistence, ident: &str) -> Result<(), String> {
    let mut servers = store::load_servers(p)?;
    let before = servers.len();
    servers.retain(|s| !(s.id == ident || s.name.as_deref() == Some(ident)));
    if servers.len() == before {
        return Err(format!("서버를 찾을 수 없음: {ident}"));
    }
    store::save_servers(p, &servers)?;
    println!("삭제됨: {ident}");
    Ok(())
}

/// id 또는 name으로 단건 서버 상세를 출력한다.
fn server_show(p: &dyn Persistence, ident: &str) -> Result<(), String> {
    let servers = store::load_servers(p)?;
    match store::find(&servers, ident) {
        Some(s) => {
            println!("id:   {}", s.id);
            println!("name: {}", s.name.as_deref().unwrap_or("-"));
            println!("user: {}", s.user);
            println!("host: {}", s.host);
            println!("port: {}", s.port);
            Ok(())
        }
        None => Err(format!("서버를 찾을 수 없음: {ident}")),
    }
}

/// 저장된 서버를 ID / NAME / TARGET 테이블로 포맷한다(순수). `format_table`의 형제.
fn format_server_table(servers: &[Server]) -> String {
    let name_cell = |s: &Server| s.name.as_deref().unwrap_or("-").to_string();
    let id_w = "ID"
        .len()
        .max(servers.iter().map(|s| s.id.len()).max().unwrap_or(0));
    let name_w = "NAME".len().max(
        servers
            .iter()
            .map(|s| name_cell(s).len())
            .max()
            .unwrap_or(0),
    );

    let mut out = format!("{:<id_w$} {:<name_w$} {}", "ID", "NAME", "TARGET");
    for s in servers {
        out.push('\n');
        out.push_str(&format!(
            "{:<id_w$} {:<name_w$} {}@{}:{}",
            s.id,
            name_cell(s),
            s.user,
            s.host,
            s.port
        ));
    }
    out
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Server { action } => run_server(action),

        Commands::Scan {
            target,
            port,
            range,
            json,
        } => {
            let store = store::FileStore::new(store::config_dir());
            let server = resolve_server(&store, &target, port).unwrap_or_else(|msg| {
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

        Commands::Tunnel {
            target,
            forward,
            port,
        } => {
            let store = store::FileStore::new(store::config_dir());
            let server = resolve_server(&store, &target, port).unwrap_or_else(|msg| {
                eprintln!("error: {msg}");
                std::process::exit(1);
            });
            let spec = parse_forward_spec(&forward).unwrap_or_else(|msg| {
                eprintln!("error: {msg}");
                std::process::exit(1);
            });

            // core가 단일 출처: argv 조립·spawn·early-death 감지(1500ms settle)를 위임한다.
            let id = format!("{}:{}", spec.local_port, spec.remote_port);
            match tunnel::start_forwarding(
                &ProcessTunnelSpawner,
                id,
                &server,
                &spec,
                Duration::from_millis(1500),
            ) {
                Ok((forwarding, mut process)) => {
                    println!(
                        "tunnel {:?}: 127.0.0.1:{} → {}:{}  (Ctrl-C to stop)",
                        forwarding.state,
                        forwarding.local_port,
                        spec.remote_host,
                        forwarding.remote_port
                    );
                    // foreground: core 핸들엔 wait()가 없으므로 poll_exit로 종료까지 폴링한다.
                    // Ctrl-C는 프로세스 그룹으로 ssh 자식에 전파된다(기존 동작 유지).
                    while process.poll_exit().is_none() {
                        std::thread::sleep(Duration::from_millis(200));
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

// ── tunnel ──────────────────────────────────────────────────────────────

/// `-L` 인자를 core [`ForwardSpec`]로 파싱한다(순수). 3-part 형식 검증과 remote_host
/// 비어있음 거부는 CLI 책임(`-L <local_port>:<remote_host>:<remote_port>`).
fn parse_forward_spec(spec: &str) -> Result<ForwardSpec, String> {
    let parts: Vec<&str> = spec.split(':').collect();
    if parts.len() != 3 {
        return Err(format!(
            "-L must be <local_port>:<remote_host>:<remote_port> (got '{spec}')"
        ));
    }
    let local_port = parts[0]
        .parse::<u16>()
        .map_err(|_| format!("invalid local port: {}", parts[0]))?;
    let remote_host = parts[1].to_string();
    if remote_host.is_empty() {
        return Err("remote host must not be empty".to_string());
    }
    let remote_port = parts[2]
        .parse::<u16>()
        .map_err(|_| format!("invalid remote port: {}", parts[2]))?;
    Ok(ForwardSpec {
        remote_port,
        local_port,
        remote_host,
    })
}

// ── core TunnelSpawner 구현 (실 프로세스) ─────────────────────────────────
//
// core `tunnel`은 무상태·주입형(#105)이라 실제 ssh 실행은 소비처가 구현한다. argv
// 조립(`forward_args`)·시작·early-death 감지(`start_forwarding`)는 core가 단일 소유하고,
// CLI는 std::process 글루만 제공한다. (Tauri `tunnel_runtime.rs`와 같은 소비처 패턴.)

/// `std::process::Child` 기반 [`TunnelProcess`]. stderr는 별도 스레드로 드레인해
/// 조기 사망 시 사유 스냅샷을 제공한다(장수명 터널 파이프 포화 방지).
struct ChildTunnelProcess {
    child: Child,
    pid: u32,
    stderr_handle: Option<std::thread::JoinHandle<String>>,
}

impl ChildTunnelProcess {
    fn new(mut child: Child) -> Self {
        let pid = child.id();
        let stderr_handle = child.stderr.take().map(|mut pipe| {
            std::thread::spawn(move || {
                let mut buf = Vec::new();
                let _ = pipe.read_to_end(&mut buf);
                String::from_utf8_lossy(&buf).trim().to_string()
            })
        });
        Self {
            child,
            pid,
            stderr_handle,
        }
    }

    fn drain_stderr(&mut self) -> String {
        match self.stderr_handle.take() {
            Some(h) => h.join().unwrap_or_default(),
            None => String::new(),
        }
    }
}

impl TunnelProcess for ChildTunnelProcess {
    fn poll_exit(&mut self) -> Option<String> {
        match self.child.try_wait() {
            Ok(Some(_status)) => Some(self.drain_stderr()),
            Ok(None) => None,
            Err(e) => Some(format!("try_wait failed: {e}")),
        }
    }

    fn kill(&mut self) -> std::io::Result<()> {
        self.child.kill()?;
        let _ = self.child.wait(); // 좀비 회수
        Ok(())
    }

    fn pid(&self) -> u32 {
        self.pid
    }
}

/// ssh를 자식 프로세스로 띄우는 [`TunnelSpawner`]. core가 조립한 argv를 그대로 실행한다.
struct ProcessTunnelSpawner;

impl TunnelSpawner for ProcessTunnelSpawner {
    fn spawn(
        &self,
        executable: &str,
        args: &[&str],
    ) -> Result<Box<dyn TunnelProcess>, PortBridgeError> {
        let child = Command::new(executable)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| PortBridgeError::ForwardingDiedEarly {
                stderr: format!("spawn failed: {e}"),
            })?;
        Ok(Box::new(ChildTunnelProcess::new(child)))
    }
}

// ── 유틸리티 ────────────────────────────────────────────────────────────

/// 스캔 대상을 `Server`로 해석한다.
///
/// 대상 토큰을 `Server`로 해석한다 (scan/tunnel 공용).
///
/// 우선순위: `@` 포함 → literal `user@host`. bare 토큰 → ① 저장 서버의 name/id 일치,
/// 없으면 ② `~/.ssh/config`의 Host alias(core `resolve_host` 소비), 둘 다 없으면 에러.
/// name↔alias 충돌 시 사용자가 명시 저장한 저장 서버를 우선한다.
///
/// 포트 우선순위: 명시 `--port`/`-p` > 저장 서버·config Port > 22.
fn resolve_server(
    p: &dyn Persistence,
    target: &str,
    explicit_port: Option<u16>,
) -> Result<Server, String> {
    if target.contains('@') {
        let (user, host) =
            split_target(target).ok_or_else(|| "target must be in user@host format".to_string())?;
        return Ok(Server {
            id: format!("{user}@{host}"),
            name: None,
            user,
            host,
            port: explicit_port.unwrap_or(22),
        });
    }

    // ① 저장 서버 (name 또는 id)
    let servers = store::load_servers(p)?;
    if let Some(saved) = store::find(&servers, target) {
        let mut server = saved.clone();
        if let Some(port) = explicit_port {
            server.port = port;
        }
        return Ok(server);
    }

    // ② ssh-config Host alias
    match resolve_host(&HostPlatform, target) {
        Ok(Some(resolved)) => server_from_resolved(target, resolved, explicit_port),
        Ok(None) => Err(format!(
            "no saved server or ~/.ssh/config alias '{target}' (use user@host)"
        )),
        Err(error) => Err(error.to_string()),
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

/// 결과를 PORT / ADDRESS / PROCESS 테이블로 포맷한 문자열로 반환한다(순수).
///
/// 컬럼 폭 = `max(헤더 라벨 길이, 그 컬럼 데이터의 최대 길이)`이라 IPv6 등 긴 주소가
/// 섞여도 정렬이 어긋나지 않는다. 좌측 정렬, 마지막 `PROCESS` 컬럼은 trailing
/// whitespace 없이. `process_name`이 `None`이면 `-`.
fn format_table(ports: &[RemotePort]) -> String {
    let port_cells: Vec<String> = ports.iter().map(|rp| rp.port.to_string()).collect();
    let process = |rp: &RemotePort| rp.process_name.as_deref().unwrap_or("-").to_string();

    let port_w = "PORT"
        .len()
        .max(port_cells.iter().map(String::len).max().unwrap_or(0));
    let addr_w = "ADDRESS"
        .len()
        .max(ports.iter().map(|rp| rp.address.len()).max().unwrap_or(0));

    let mut out = format!("{:<port_w$} {:<addr_w$} {}", "PORT", "ADDRESS", "PROCESS");
    for (i, rp) in ports.iter().enumerate() {
        out.push('\n');
        out.push_str(&format!(
            "{:<port_w$} {:<addr_w$} {}",
            port_cells[i],
            rp.address,
            process(rp)
        ));
    }
    out
}

/// `format_table`의 결과를 출력하는 얇은 래퍼.
fn print_table(ports: &[RemotePort]) {
    println!("{}", format_table(ports));
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

    /// 단위 테스트용 인메모리 [`Persistence`] — 미리 주입한 서버 목록을 돌려준다.
    struct FakePersistence {
        servers_json: Option<String>,
    }

    impl FakePersistence {
        fn empty() -> Self {
            Self { servers_json: None }
        }

        fn with(servers: &[Server]) -> Self {
            Self {
                servers_json: Some(serde_json::to_string(servers).unwrap()),
            }
        }
    }

    impl Persistence for FakePersistence {
        fn load(
            &self,
            key: &str,
        ) -> Result<Option<String>, portbridge_core::persistence::PersistenceError> {
            if key == portbridge_core::persistence::SERVERS_KEY {
                Ok(self.servers_json.clone())
            } else {
                Ok(None)
            }
        }

        fn save(
            &self,
            _key: &str,
            _value: &str,
        ) -> Result<(), portbridge_core::persistence::PersistenceError> {
            Ok(())
        }
    }

    fn saved_server(name: Option<&str>, user: &str, host: &str, port: u16) -> Server {
        Server {
            id: format!("id-{host}-{port}"),
            name: name.map(str::to_string),
            user: user.to_string(),
            host: host.to_string(),
            port,
        }
    }

    // ── resolve_server: user@host literal ──────────────────────────────────

    #[test]
    fn user_host_target_builds_server_with_default_port() {
        let server = resolve_server(&FakePersistence::empty(), "deploy@10.0.0.1", None).unwrap();
        assert_eq!(server.user, "deploy");
        assert_eq!(server.host, "10.0.0.1");
        assert_eq!(server.port, 22);
        assert_eq!(server.name, None);
    }

    #[test]
    fn user_host_target_uses_explicit_port() {
        let server =
            resolve_server(&FakePersistence::empty(), "deploy@10.0.0.1", Some(2022)).unwrap();
        assert_eq!(server.port, 2022);
    }

    #[test]
    fn malformed_user_host_target_is_error() {
        assert!(resolve_server(&FakePersistence::empty(), "@host", None).is_err());
    }

    // ── resolve_server: 저장 서버 (name/id) ────────────────────────────────

    /// bare 토큰이 저장 서버 name과 일치하면 그 서버(포트 포함)를 쓴다.
    #[test]
    fn bare_target_matches_saved_server_by_name() {
        let p = FakePersistence::with(&[saved_server(Some("prod"), "ubuntu", "10.0.0.1", 2222)]);
        let server = resolve_server(&p, "prod", None).unwrap();
        assert_eq!(server.user, "ubuntu");
        assert_eq!(server.host, "10.0.0.1");
        assert_eq!(server.port, 2222);
    }

    /// 저장 서버를 id로도 찾을 수 있다.
    #[test]
    fn bare_target_matches_saved_server_by_id() {
        let p = FakePersistence::with(&[saved_server(Some("prod"), "ubuntu", "10.0.0.1", 2222)]);
        let server = resolve_server(&p, "id-10.0.0.1-2222", None).unwrap();
        assert_eq!(server.host, "10.0.0.1");
    }

    /// 명시 포트는 저장 서버 포트를 override한다.
    #[test]
    fn explicit_port_overrides_saved_server_port() {
        let p = FakePersistence::with(&[saved_server(Some("prod"), "ubuntu", "10.0.0.1", 2222)]);
        let server = resolve_server(&p, "prod", Some(2022)).unwrap();
        assert_eq!(server.port, 2022);
    }

    // 주: "저장도 alias도 없을 때 에러" 경로는 `resolve_server`가 실제 `~/.ssh/config`를
    // 읽는 `resolve_host(&HostPlatform, ..)`로 폴백하므로 환경 의존적이다(예: `Host *`
    // 와일드카드가 있으면 임의 토큰도 매칭). 환경 독립 단위 테스트로 만들려면 플랫폼
    // 주입이 필요하며, 이는 별도 정리 트랙으로 둔다. alias 매핑 자체는 `server_from_resolved`
    // 순수 테스트가 커버한다.

    // ── tunnel (-L 파싱 + Forwarding 구성) ─────────────────────────────────

    #[test]
    fn parse_forward_spec_valid() {
        assert_eq!(
            parse_forward_spec("8080:127.0.0.1:80"),
            Ok(ForwardSpec {
                remote_port: 80,
                local_port: 8080,
                remote_host: "127.0.0.1".to_string(),
            })
        );
    }

    /// 비-localhost remote_host가 core `forward_args` argv에 그대로 전달되는지
    /// (Stage 2 통합 후에도 임의 호스트 포워딩 기능 회귀 없음).
    #[test]
    fn parse_forward_spec_preserves_arbitrary_remote_host_in_argv() {
        let spec = parse_forward_spec("8080:10.0.0.5:5432").expect("valid spec");
        let server = Server {
            id: "deploy@10.0.0.1".into(),
            name: None,
            user: "deploy".into(),
            host: "10.0.0.1".into(),
            port: 22,
        };
        let args = tunnel::forward_args(&server, &spec);
        assert!(args.iter().any(|a| a == "8080:10.0.0.5:5432"));
    }

    #[test]
    fn parse_forward_spec_wrong_part_count() {
        assert!(parse_forward_spec("8080:80").is_err()); // 2 parts
        assert!(parse_forward_spec("8080:h:80:extra").is_err()); // 4 parts
    }

    #[test]
    fn parse_forward_spec_out_of_range_port() {
        assert!(parse_forward_spec("99999:h:80").is_err()); // > u16
        assert!(parse_forward_spec("8080:h:99999").is_err());
    }

    #[test]
    fn parse_forward_spec_empty_remote_host() {
        assert!(parse_forward_spec("8080::80").is_err());
    }

    #[test]
    fn parse_forward_spec_non_numeric_port() {
        assert!(parse_forward_spec("abc:h:80").is_err());
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

    // ── format_table ─────────────────────────────────────────────────────

    /// 20자를 초과하는 IPv6 주소가 섞여도 PROCESS 컬럼이 모든 줄에서 같은 오프셋에서
    /// 시작해야 한다(고정 20자 폭에서는 어긋나 실패하는 회귀 테스트).
    #[test]
    fn format_table_aligns_process_column_with_long_address() {
        let ports = vec![
            RemotePort {
                port: 22,
                address: "::1".into(),
                process_name: Some("sshd".into()),
            },
            RemotePort {
                port: 8080,
                address: "fe80::1ff:fe23:4567:890a".into(), // 24자 > 고정 20자
                process_name: Some("nginx".into()),
            },
        ];
        let table = format_table(&ports);
        let lines: Vec<&str> = table.lines().collect();
        // PROCESS는 마지막(패딩 없는) 컬럼 → 값이 줄의 suffix. 시작 오프셋 = len - 값길이.
        assert!(lines[0].ends_with("PROCESS"));
        let offset = lines[0].len() - "PROCESS".len();
        assert!(lines[1].ends_with("sshd"));
        assert_eq!(lines[1].len() - "sshd".len(), offset);
        assert!(lines[2].ends_with("nginx"));
        assert_eq!(lines[2].len() - "nginx".len(), offset);
    }

    /// 빈 입력에서도 헤더가 헤더 라벨 폭으로 정렬된다.
    #[test]
    fn format_table_empty_aligns_to_header_labels() {
        assert_eq!(format_table(&[]), "PORT ADDRESS PROCESS");
    }

    /// process_name이 None인 행은 `-`로 렌더된다.
    #[test]
    fn format_table_none_process_renders_dash() {
        let ports = vec![RemotePort {
            port: 22,
            address: "10.0.0.1".into(),
            process_name: None,
        }];
        let table = format_table(&ports);
        assert!(table.lines().nth(1).unwrap().ends_with('-'));
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

    // ── server CRUD ───────────────────────────────────────────────────────

    /// 테이블: 헤더 정렬 + None name은 `-`, TARGET은 user@host:port.
    #[test]
    fn format_server_table_aligns_and_handles_none_name() {
        let servers = vec![
            Server {
                id: "srv-1".into(),
                name: Some("prod".into()),
                user: "ubuntu".into(),
                host: "10.0.0.1".into(),
                port: 2222,
            },
            Server {
                id: "srv-22".into(),
                name: None,
                user: "deploy".into(),
                host: "h".into(),
                port: 22,
            },
        ];
        let lines: Vec<String> = format_server_table(&servers)
            .lines()
            .map(str::to_string)
            .collect();
        assert!(lines[0].starts_with("ID"));
        assert!(lines[1].ends_with("ubuntu@10.0.0.1:2222"));
        assert!(lines[2].contains(" - ") && lines[2].ends_with("deploy@h:22"));
    }

    /// add는 영속·중복 거부, rm은 name으로 삭제·부재 시 에러(엔드투엔드, 파일 백엔드).
    #[test]
    fn server_add_persists_rejects_dup_and_rm_removes() {
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let n = N.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("pb_cli_srv_{}_{}", std::process::id(), n));
        let _ = std::fs::remove_dir_all(&dir);
        let p = store::FileStore::new(dir.clone());

        server_add(&p, "deploy@10.0.0.1", Some("prod".into()), 22).unwrap();
        let servers = store::load_servers(&p).unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0].name.as_deref(), Some("prod"));

        // 같은 (user,host,port) 재추가 거부
        assert!(server_add(&p, "deploy@10.0.0.1", None, 22).is_err());
        // 같은 host 다른 port는 허용
        server_add(&p, "deploy@10.0.0.1", None, 2222).unwrap();
        assert_eq!(store::load_servers(&p).unwrap().len(), 2);

        // name으로 삭제
        server_rm(&p, "prod").unwrap();
        assert_eq!(store::load_servers(&p).unwrap().len(), 1);
        // 없는 것 삭제 → 에러
        assert!(server_rm(&p, "prod").is_err());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
