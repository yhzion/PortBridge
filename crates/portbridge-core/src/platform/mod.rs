//! OS별로 갈리는 로컬 작업(로컬 명령 실행, 자식 프로세스 종료, config 경로)의
//! 플랫폼 경계. 이후 ssh-config/tunnel/scan 포팅이 이 trait 위에 올라간다.
//!
//! core는 의존성 0개를 유지한다 — 프로세스 종료는 플랫폼 도구(`kill`/`taskkill`)로
//! shell-out하며, libc/windows-sys 등 신규 의존을 도입하지 않는다(루트 `Cargo.lock`
//! serial-only, AGENTS §2).

use std::path::{Path, PathBuf};
use std::process::{Child, Command};

#[cfg(unix)]
mod unix;
#[cfg(windows)]
mod windows;

/// 현재 OS에 해당하는 플랫폼 구현 (`#[cfg]`로 선택).
#[cfg(unix)]
pub use unix::UnixPlatform as HostPlatform;
#[cfg(windows)]
pub use windows::WindowsPlatform as HostPlatform;

/// OS별로 갈리는 로컬 작업의 추상 경계.
pub trait Platform {
    /// SSH config 디렉터리(`~/.ssh`). 홈 디렉터리 환경변수 미설정 시 `None`.
    fn config_dir(&self) -> Option<PathBuf>;

    /// PID로 로컬 프로세스를 종료한다 (unix: `kill`/SIGTERM, windows: `taskkill`).
    fn kill_process(&self, pid: u32) -> std::io::Result<()>;

    /// 로컬 명령을 자식 프로세스로 spawn한다. `std::process`는 크로스 플랫폼이므로
    /// 기본 구현을 공유한다.
    fn spawn(&self, executable: &str, args: &[&str]) -> std::io::Result<Child> {
        Command::new(executable).args(args).spawn()
    }
}

/// 홈 디렉터리로부터 `~/.ssh` config 경로를 조립하는 순수 함수.
///
/// 디렉터리 이름(`.ssh`)은 플랫폼 공통이며, 홈 위치 결정(HOME vs USERPROFILE)은
/// 각 [`Platform`] 구현이 담당한다.
pub(crate) fn ssh_config_dir(home: &Path) -> PathBuf {
    home.join(".ssh")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ssh_config_dir_appends_dot_ssh() {
        assert_eq!(
            ssh_config_dir(Path::new("/home/alice")),
            PathBuf::from("/home/alice/.ssh")
        );
    }
}
