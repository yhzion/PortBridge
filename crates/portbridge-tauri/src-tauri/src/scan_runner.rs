//! core `scan::scan`에 주입할 `CommandRunner` 구현 — `std::process`로 ssh를 실행한다.
//!
//! CLI `ProcessRunner`(#37)와 동형: 별도 스레드로 stdout/stderr를 드레인해 파이프 포화
//! 데드락을 막고, try_wait 폴링으로 타임아웃 시 자식을 kill·회수한다. FFI(Swift)는
//! uniffi 콜백이라 재사용 불가하므로 Tauri는 Rust 네이티브로 별도 구현한다.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use portbridge_core::scan::{CommandError, CommandResult, CommandRunner};

/// ssh를 자식 프로세스로 실행하는 동기 러너.
pub struct ProcessRunner;

impl CommandRunner for ProcessRunner {
    fn run(
        &self,
        executable: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<CommandResult, CommandError> {
        let mut child = Command::new(executable)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| CommandError::LaunchFailed(e.to_string()))?;

        // 파이프를 별도 스레드에서 드레인 — 버퍼 포화로 자식이 멈추는 것을 막는다.
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

        let deadline = Instant::now() + timeout;
        let exit_status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {
                    if Instant::now() >= deadline {
                        let _ = child.kill();
                        let _ = child.wait();
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

#[cfg(test)]
mod tests {
    use super::*;

    // 실제 프로세스 경로 — 로컬 셸 도구로 러너 계약(exit/stdout/stderr/timeout)을 검증한다.
    // ssh 자체가 아니라 CommandRunner 구현의 동작을 본다(ssh 통합은 S5).

    #[test]
    fn run_captures_stdout_and_exit_zero() {
        let r = ProcessRunner
            .run("/bin/sh", &["-c", "printf hello"], Duration::from_secs(5))
            .expect("should run");
        assert_eq!(r.exit_code, 0);
        assert_eq!(r.stdout, "hello");
    }

    #[test]
    fn run_captures_stderr_and_nonzero_exit() {
        let r = ProcessRunner
            .run(
                "/bin/sh",
                &["-c", "printf oops >&2; exit 3"],
                Duration::from_secs(5),
            )
            .expect("should run");
        assert_eq!(r.exit_code, 3);
        assert_eq!(r.stderr, "oops");
    }

    #[test]
    fn run_times_out_and_kills_child() {
        let err = ProcessRunner
            .run("/bin/sh", &["-c", "sleep 5"], Duration::from_millis(100))
            .expect_err("should time out");
        assert_eq!(err, CommandError::TimedOut);
    }

    #[test]
    fn run_launch_failure_is_reported() {
        let err = ProcessRunner
            .run("/nonexistent/binary/xyz", &[], Duration::from_secs(1))
            .expect_err("should fail to launch");
        assert!(matches!(err, CommandError::LaunchFailed(_)));
    }
}
