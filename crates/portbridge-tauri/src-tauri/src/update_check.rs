//! 업데이트 체크(#133 항목5) — core `update::ReleaseFetcher`의 GitHub HTTP 구현 + 트레이 트리거.
//!
//! 버전 파싱·비교·판정은 core(`update::check_update`/`version`)가 전담(이미 단위 테스트됨,
//! macOS FFI와 동일 SSOT). 여기는 네트워크 I/O 글루만 — macOS `GitHubReleaseFetcher`의
//! 엔드포인트·헤더를 그대로 맞춘다. 동기 `ureq`로 core의 동기 trait을 충족.
//!
//! 검증: 네트워크 I/O라 헤드리스 단위 검증 불가(빌드만). 판정 로직은 core 테스트가 커버.
//! 실제 동작은 실 macOS/네트워크 환경 수동 검증.

use std::time::Duration;

use portbridge_core::update::{check_update, ReleaseFetcher, UpdateError, UpdateStatus};
use portbridge_core::version::{parse_semver, ReleaseInfo};

const OWNER: &str = "yhzion";
const REPO: &str = "PortBridge";

/// GitHub `releases/latest`를 조회하는 [`ReleaseFetcher`]. macOS 구현과 동일 계약.
struct GitHubReleaseFetcher {
    user_agent: String,
}

impl ReleaseFetcher for GitHubReleaseFetcher {
    fn fetch_latest(&self) -> Result<ReleaseInfo, UpdateError> {
        let url = format!("https://api.github.com/repos/{OWNER}/{REPO}/releases/latest");
        let resp = ureq::get(&url)
            .set("Accept", "application/vnd.github+json")
            .set("X-GitHub-Api-Version", "2022-11-28")
            // GitHub API는 User-Agent 없으면 403 → 없으면 조용히 "업데이트 없음"이 됨.
            .set("User-Agent", &self.user_agent)
            .timeout(Duration::from_secs(10))
            .call();

        match resp {
            Ok(r) => {
                let body = r
                    .into_string()
                    .map_err(|e| UpdateError::Network(e.to_string()))?;
                serde_json::from_str::<ReleaseInfo>(&body)
                    .map_err(|e| UpdateError::Decoding(e.to_string()))
            }
            Err(ureq::Error::Status(code, _)) => Err(UpdateError::HttpStatus(code)),
            Err(ureq::Error::Transport(t)) => Err(UpdateError::Network(t.to_string())),
        }
    }
}

/// 수동 업데이트 체크(트레이 메뉴). 더 새 릴리스면 릴리스 페이지를 브라우저로 연다.
/// 현재 버전 파싱 불가/최신/조회실패는 (현 단계) 비가시 — 로깅만. 자동체크·결과 알림은 후속.
///
/// `current_app_version`은 **앱 버전**(tauri.conf.json, `app.package_info().version`)을 넘긴다.
/// `core::version()`은 core 라이브러리 버전(0.0.0)이라 릴리스 태그와 무관 → 쓰면 항상
/// "업데이트 있음"이 되는 버그. 비교 대상은 반드시 앱 버전.
pub fn check_now(current_app_version: &str) {
    let Some(current) = parse_semver(current_app_version) else {
        eprintln!("update-check: 앱 버전('{current_app_version}') 파싱 불가 — 비교 생략");
        return;
    };
    let fetcher = GitHubReleaseFetcher {
        user_agent: format!("PortBridge/{current_app_version}"),
    };
    match check_update(&current, &fetcher) {
        UpdateStatus::Available { version, url } => {
            eprintln!("update-check: 새 버전 {version} 발견 → {url} 열기");
            let _ = open::that(url);
        }
        UpdateStatus::UpToDate => eprintln!("update-check: 최신 버전"),
        UpdateStatus::Error(e) => eprintln!("update-check: 조회 실패 — {e}"),
    }
}
