//! 업데이트 체크 — 최신 릴리스 조회(주입형) → 현재 버전 비교 → 상태 판정.
//!
//! Swift `ReleaseFetcher`/`UpdateChecker`의 결정 흐름을 포팅한다. HTTP는
//! [`ReleaseFetcher`] trait로 주입해 core를 네트워크-free·테스트 가능하게 둔다
//! (scan의 `CommandRunner`와 같은 입장). UI 상태(phase/presenter)·skip·주기 판정·
//! 영속화는 core 밖(플랫폼 소비자)이며, core는 순수 판정([`check_update`])만 한다.

use crate::version::{ReleaseInfo, SemanticVersion};

/// 업데이트 조회 실패 원인. Swift `UpdateCheckError` 매핑.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UpdateError {
    Network(String),
    HttpStatus(u16),
    Decoding(String),
    InvalidResponse,
}

impl std::fmt::Display for UpdateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Network(reason) => write!(f, "network error: {reason}"),
            Self::HttpStatus(code) => write!(f, "HTTP {code}"),
            Self::Decoding(reason) => write!(f, "decoding error: {reason}"),
            Self::InvalidResponse => write!(f, "invalid response"),
        }
    }
}

impl std::error::Error for UpdateError {}

/// 최신 릴리스 조회 경계(주입형 HTTP). 동기 — 비동기 브릿지는 소비자 몫.
pub trait ReleaseFetcher {
    fn fetch_latest(&self) -> Result<ReleaseInfo, UpdateError>;
}

/// 업데이트 체크 결과.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UpdateStatus {
    /// 최신이거나, 더 새 버전이 아니거나, 릴리스 태그를 파싱할 수 없음.
    UpToDate,
    /// 더 새 버전이 존재.
    Available {
        version: SemanticVersion,
        url: String,
    },
    /// 조회 실패.
    Error(UpdateError),
}

/// 최신 릴리스를 조회해 현재 버전과 비교하고 [`UpdateStatus`]를 판정한다.
///
/// 조회 실패 → `Error`. 릴리스 태그가 파싱 불가하거나 현재 버전보다 새롭지 않으면
/// `UpToDate`(Swift도 remote.version nil 시 upToDate). 더 새 버전이면 `Available`.
pub fn check_update<F: ReleaseFetcher + ?Sized>(
    current: &SemanticVersion,
    fetcher: &F,
) -> UpdateStatus {
    match fetcher.fetch_latest() {
        Err(error) => UpdateStatus::Error(error),
        Ok(release) => match release.version() {
            Some(remote) if remote > *current => UpdateStatus::Available {
                version: remote,
                url: release.html_url,
            },
            _ => UpdateStatus::UpToDate,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 단위 테스트용 fake — 미리 정한 결과를 반환한다.
    struct FakeFetcher(Result<ReleaseInfo, UpdateError>);

    impl ReleaseFetcher for FakeFetcher {
        fn fetch_latest(&self) -> Result<ReleaseInfo, UpdateError> {
            self.0.clone()
        }
    }

    fn release(tag: &str, url: &str) -> ReleaseInfo {
        ReleaseInfo {
            tag_name: tag.to_string(),
            name: None,
            html_url: url.to_string(),
            published_at: None,
            body: None,
        }
    }

    #[test]
    fn available_when_release_is_newer() {
        let current = SemanticVersion::new(1, 2, 0);
        let fetcher = FakeFetcher(Ok(release("v1.3.0", "https://example/r")));
        assert_eq!(
            check_update(&current, &fetcher),
            UpdateStatus::Available {
                version: SemanticVersion::new(1, 3, 0),
                url: "https://example/r".to_string(),
            }
        );
    }

    #[test]
    fn up_to_date_when_not_newer() {
        let current = SemanticVersion::new(1, 3, 0);
        assert_eq!(
            check_update(&current, &FakeFetcher(Ok(release("1.3.0", "u")))),
            UpdateStatus::UpToDate
        );
        assert_eq!(
            check_update(&current, &FakeFetcher(Ok(release("1.2.9", "u")))),
            UpdateStatus::UpToDate
        );
    }

    #[test]
    fn up_to_date_when_tag_unparseable() {
        let current = SemanticVersion::new(1, 0, 0);
        assert_eq!(
            check_update(&current, &FakeFetcher(Ok(release("nightly", "u")))),
            UpdateStatus::UpToDate
        );
    }

    #[test]
    fn error_when_fetch_fails() {
        let current = SemanticVersion::new(1, 0, 0);
        let fetcher = FakeFetcher(Err(UpdateError::Network("offline".to_string())));
        assert_eq!(
            check_update(&current, &fetcher),
            UpdateStatus::Error(UpdateError::Network("offline".to_string()))
        );
    }
}
