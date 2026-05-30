//! Windows 플랫폼 구현 (`#[cfg(windows)]`).
//!
//! 로컬 macOS 환경에서는 cfg로 제외되어 컴파일되지 않는다 — 컴파일/동작 검증은
//! 크로스플랫폼 CI 매트릭스(#60)에서 수행한다.

use std::path::{Path, PathBuf};
use std::process::Command;

use super::{ssh_config_dir, Platform};

/// Windows의 [`Platform`] 구현.
pub struct WindowsPlatform;

impl Platform for WindowsPlatform {
    fn config_dir(&self) -> Option<PathBuf> {
        std::env::var_os("USERPROFILE").map(|home| ssh_config_dir(Path::new(&home)))
    }

    fn kill_process(&self, pid: u32) -> std::io::Result<()> {
        let status = Command::new("taskkill")
            .args(["/PID", &pid.to_string(), "/F"])
            .status()?;
        if status.success() {
            Ok(())
        } else {
            Err(std::io::Error::other(format!(
                "taskkill {pid} failed: {status}"
            )))
        }
    }
}
