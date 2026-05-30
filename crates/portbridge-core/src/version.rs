//! 버전 도메인 — SemVer 파싱·비교 + 릴리스 메타. 네트워크 없는 순수 로직.
//!
//! Swift `SemanticVersion`/`ReleaseInfo`/`BundleVersion`의 순수 도메인을 포팅한다.
//! Swift `SemanticVersion`은 단순 `major.minor[.patch]`만 받는다 — 숫자와 `.`만
//! 허용하고 프리릴리스/빌드메타(`-`/`+`)는 거부한다(파싱 실패). 이 동작을 그대로
//! 따른다. 번들 버전 읽기(`CFBundleShortVersionString`)는 플랫폼 몫이며, 그 문자열을
//! [`parse_semver`]로 파싱하는 것이 core 책임이다.

use serde::Deserialize;

/// `major.minor.patch` 시맨틱 버전. 비교는 (major, minor, patch) 사전순.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SemanticVersion {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

impl SemanticVersion {
    pub fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self {
            major,
            minor,
            patch,
        }
    }
}

impl std::fmt::Display for SemanticVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

/// 버전 문자열을 파싱한다(Swift `SemanticVersion(string:)` 동치).
///
/// 선행 `v`를 제거하고, 숫자와 `.`만 허용한다(그 외 문자가 있으면 `None`). `.`로
/// 분리한 파트는 정확히 2개(patch=0) 또는 3개여야 하며, 빈 파트는 실패다. 즉
/// `1.2.3-alpha`/`1.2.3+build`처럼 프리릴리스/빌드메타가 붙으면 `None`이다.
pub fn parse_semver(input: &str) -> Option<SemanticVersion> {
    let s = input.strip_prefix('v').unwrap_or(input);
    if s.is_empty() || !s.chars().all(|c| c.is_ascii_digit() || c == '.') {
        return None;
    }
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() != 2 && parts.len() != 3 {
        return None;
    }
    let major = parts[0].parse::<u32>().ok()?;
    let minor = parts[1].parse::<u32>().ok()?;
    let patch = if parts.len() == 3 {
        parts[2].parse::<u32>().ok()?
    } else {
        0
    };
    Some(SemanticVersion::new(major, minor, patch))
}

/// GitHub 릴리스 메타. Swift `ReleaseInfo` 매핑. GitHub release JSON의 추가 필드는
/// serde가 무시한다(필드명이 곧 snake_case JSON 키다).
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct ReleaseInfo {
    pub tag_name: String,
    pub name: Option<String>,
    pub html_url: String,
    pub published_at: Option<String>,
    pub body: Option<String>,
}

impl ReleaseInfo {
    /// `tag_name`을 [`SemanticVersion`]으로 파싱한다(파싱 불가 시 `None`).
    pub fn version(&self) -> Option<SemanticVersion> {
        parse_semver(&self.tag_name)
    }
}

/// 현재 버전 대비 릴리스가 더 새 버전이면 `true`. `tag_name`이 파싱 불가면 `false`.
pub fn update_available(current: &SemanticVersion, latest: &ReleaseInfo) -> bool {
    latest.version().is_some_and(|v| v > *current)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── parse_semver ──────────────────────────────────────────────────────

    #[test]
    fn parses_three_part() {
        assert_eq!(parse_semver("1.2.3"), Some(SemanticVersion::new(1, 2, 3)));
    }

    #[test]
    fn parses_two_part_patch_defaults_zero() {
        assert_eq!(parse_semver("1.2"), Some(SemanticVersion::new(1, 2, 0)));
    }

    #[test]
    fn strips_leading_v() {
        assert_eq!(parse_semver("v2.0.1"), Some(SemanticVersion::new(2, 0, 1)));
    }

    /// Swift 파서는 프리릴리스/빌드메타를 거부한다(숫자·점만 허용).
    #[test]
    fn rejects_prerelease_and_build_metadata() {
        assert_eq!(parse_semver("1.2.3-alpha"), None);
        assert_eq!(parse_semver("1.2.3+build"), None);
    }

    #[test]
    fn rejects_wrong_part_count() {
        assert_eq!(parse_semver("1"), None); // 1 파트
        assert_eq!(parse_semver("1.2.3.4"), None); // 4 파트
    }

    #[test]
    fn rejects_empty_and_non_numeric_parts() {
        assert_eq!(parse_semver(""), None);
        assert_eq!(parse_semver("v"), None);
        assert_eq!(parse_semver("1..3"), None); // 빈 minor
        assert_eq!(parse_semver("1.x.3"), None);
        assert_eq!(parse_semver("1.2."), None); // 빈 patch
    }

    // ── 비교 (Swift SemanticVersion < 와 동치인 케이스 테이블) ───────────────

    #[test]
    fn ordering_matches_swift_semantics() {
        let cases = [
            ("1.2.3", "1.2.4", true),
            ("1.2.0", "1.3.0", true),
            ("1.9.9", "2.0.0", true),
            ("1.2.3", "1.2.3", false),
            ("2.0.0", "1.9.9", false),
        ];
        for (lo, hi, expect_lt) in cases {
            let a = parse_semver(lo).unwrap();
            let b = parse_semver(hi).unwrap();
            assert_eq!(a < b, expect_lt, "{lo} < {hi}");
        }
        // "1.2" 와 "1.2.0" 은 동일하다.
        assert_eq!(parse_semver("1.2"), parse_semver("1.2.0"));
    }

    // ── ReleaseInfo (serde) ─────────────────────────────────────────────────

    const GITHUB_RELEASE_JSON: &str = r#"{
        "url": "https://api.github.com/repos/x/y/releases/1",
        "id": 1,
        "tag_name": "v1.4.0",
        "name": "PortBridge 1.4.0",
        "html_url": "https://github.com/x/y/releases/tag/v1.4.0",
        "published_at": "2026-01-15T10:00:00Z",
        "body": "release notes",
        "draft": false,
        "prerelease": false,
        "assets": []
    }"#;

    #[test]
    fn release_info_deserializes_github_json_ignoring_extra_fields() {
        let release: ReleaseInfo = serde_json::from_str(GITHUB_RELEASE_JSON).unwrap();
        assert_eq!(release.tag_name, "v1.4.0");
        assert_eq!(release.name.as_deref(), Some("PortBridge 1.4.0"));
        assert_eq!(
            release.published_at.as_deref(),
            Some("2026-01-15T10:00:00Z")
        );
        assert_eq!(release.version(), Some(SemanticVersion::new(1, 4, 0)));
    }

    #[test]
    fn release_info_optional_fields_default_to_none() {
        let json = r#"{"tag_name":"1.0.0","html_url":"https://h"}"#;
        let release: ReleaseInfo = serde_json::from_str(json).unwrap();
        assert_eq!(release.name, None);
        assert_eq!(release.published_at, None);
        assert_eq!(release.body, None);
    }

    // ── update_available ────────────────────────────────────────────────────

    fn release(tag: &str) -> ReleaseInfo {
        ReleaseInfo {
            tag_name: tag.to_string(),
            name: None,
            html_url: "https://h".to_string(),
            published_at: None,
            body: None,
        }
    }

    #[test]
    fn update_available_when_release_is_newer() {
        let current = SemanticVersion::new(1, 2, 0);
        assert!(update_available(&current, &release("v1.3.0")));
    }

    #[test]
    fn no_update_when_same_or_older() {
        let current = SemanticVersion::new(1, 3, 0);
        assert!(!update_available(&current, &release("1.3.0")));
        assert!(!update_available(&current, &release("1.2.9")));
    }

    #[test]
    fn no_update_when_tag_unparseable() {
        let current = SemanticVersion::new(1, 0, 0);
        assert!(!update_available(&current, &release("nightly-build")));
    }
}
