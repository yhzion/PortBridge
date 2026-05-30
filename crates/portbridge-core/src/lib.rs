//! PortBridge 공유 코어 — 플랫폼 독립 도메인 타입과 포트 스캔 로직.

pub mod model;
pub mod persistence;
pub mod platform;
pub mod scan;
pub mod ssh_config;

/// 코어 크레이트의 패키지 버전을 반환한다.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_reported() {
        assert_eq!(version(), "0.0.0");
    }
}
