//! PortBridge 공유 코어 — SSH config 파싱, 포트 스캔, 터널 생명주기 로직의
//! 플랫폼 독립 단일 진실 공급원. 현재는 골격만 존재한다.
//! 실제 로직은 후속 이슈(#2)에서 추가한다.

/// 코어 크레이트의 패키지 버전을 반환하는 임시 골격 함수.
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
