//! Unix 플랫폼 구현 (`#[cfg(unix)]`).

use std::path::{Path, PathBuf};
use std::process::Command;

use super::{ssh_config_dir, Platform};

/// Unix 계열 OS의 [`Platform`] 구현.
pub struct UnixPlatform;

impl Platform for UnixPlatform {
    fn config_dir(&self) -> Option<PathBuf> {
        std::env::var_os("HOME").map(|home| ssh_config_dir(Path::new(&home)))
    }

    fn kill_process(&self, pid: u32) -> std::io::Result<()> {
        let status = Command::new("kill").arg(pid.to_string()).status()?;
        if status.success() {
            Ok(())
        } else {
            Err(std::io::Error::other(format!(
                "kill {pid} failed: {status}"
            )))
        }
    }
}
