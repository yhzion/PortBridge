//! `~/.ssh/config` Host alias 해석 — core가 단독 소유한다.
//!
//! 이 core API를 cli(#39/#52)·macOS(FFI)·tauri가 공유한다. 과거 macOS 앱의
//! `SSHConfigParser.swift`(폐기됨)와 동치인 동작을 포팅했다: 설정 텍스트를
//! literal Host 항목 목록으로 파싱하고, 와일드카드/부정/glob 패턴(`*`/`?`/`!`)은
//! 건너뛰며, `Include`를 재귀적으로 펼친다(cycle 검출 포함).
//!
//! 텍스트 파싱([`parse_document`])은 순수 함수다. `Include`의 파일 재귀만 I/O
//! 경계([`parse_config_file`])에 둔다. 설정 경로는 #50의 [`Platform::config_dir`]을
//! 사용하며 재정의하지 않는다.

use std::collections::HashSet;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use crate::model::PortBridgeError;
use crate::platform::Platform;

/// alias 해석 결과. 미지정 필드는 `None`(ssh 기본값 적용은 소비자 책임).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedHost {
    pub hostname: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_file: Option<String>,
}

/// 주어진 alias를 `~/.ssh/config`(+`Include`)에서 해석한다.
///
/// - 설정 파일 없음(홈 디렉터리 미설정 포함) → [`PortBridgeError::SshConfigNotFound`].
/// - 설정 파일 읽기 실패 → [`PortBridgeError::SshConfigUnreadable`].
/// - 파일은 읽혔으나 일치하는 alias 없음 → `Ok(None)`.
/// - 일치 시 → `Ok(Some(ResolvedHost))`. 같은 이름이 여러 블록에 있으면 첫 항목이 이긴다.
/// - 누락/해석불가 `Include` 대상은 비치명적으로 건너뛴다(top-level 설정 파일 없음만 에러).
pub fn resolve_host<P: Platform>(
    platform: &P,
    alias: &str,
) -> Result<Option<ResolvedHost>, PortBridgeError> {
    let Some(config_dir) = platform.config_dir() else {
        return Err(PortBridgeError::SshConfigNotFound);
    };
    resolve_in_config(&config_dir.join("config"), alias)
}

// ── 내부 ──────────────────────────────────────────────────────────────────

/// 설정 파일 경로에서 alias를 해석한다(테스트가 직접 호출).
fn resolve_in_config(
    config_path: &Path,
    alias: &str,
) -> Result<Option<ResolvedHost>, PortBridgeError> {
    let mut visited = HashSet::new();
    let entries = parse_config_file(config_path, &mut visited)?;
    Ok(entries
        .into_iter()
        .find(|entry| entry.name == alias)
        .map(HostEntry::into_resolved))
}

/// 파싱된 한 Host 항목(literal 이름 1개 + 그 블록의 옵션).
#[derive(Clone, Debug, Eq, PartialEq)]
struct HostEntry {
    name: String,
    hostname: Option<String>,
    user: Option<String>,
    port: Option<u16>,
    identity_file: Option<String>,
}

impl HostEntry {
    fn into_resolved(self) -> ResolvedHost {
        ResolvedHost {
            hostname: self.hostname,
            user: self.user,
            port: self.port,
            identity_file: self.identity_file,
        }
    }
}

/// 파싱 산출물 요소(등장 순서 보존) — Host 항목 묶음 또는 Include 지시.
#[derive(Clone, Debug, Eq, PartialEq)]
enum Element {
    Hosts(Vec<HostEntry>),
    Include(Vec<String>),
}

/// 한 블록의 누적 옵션.
#[derive(Default)]
struct BlockOptions {
    hostname: Option<String>,
    user: Option<String>,
    port: Option<u16>,
    identity_file: Option<String>,
}

/// 설정 **텍스트**를 등장 순서대로 [`Element`]로 파싱하는 순수 함수.
///
/// 와일드카드/부정/glob 패턴(`*`/`?`/`!`)을 포함한 Host 이름은 방출하지 않는다.
/// `Include`는 펼치지 않고 지시로만 남긴다(파일 I/O는 [`parse_config_file`] 담당).
fn parse_document(content: &str) -> Vec<Element> {
    let mut elements: Vec<Element> = Vec::new();
    let mut names: Option<Vec<String>> = None;
    let mut options = BlockOptions::default();

    for raw in content.lines() {
        // 첫 '#' 이후는 주석.
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let mut tokens = line.split_whitespace();
        let Some(keyword) = tokens.next() else {
            continue;
        };
        let values: Vec<&str> = tokens.collect();
        if values.is_empty() {
            continue; // keyword + value(최소 2토큰) 아니면 무시
        }

        match keyword.to_ascii_lowercase().as_str() {
            "host" => {
                flush_block(&mut names, &mut options, &mut elements);
                names = Some(values.iter().map(|s| s.to_string()).collect());
            }
            "hostname" => options.hostname = Some(values[0].to_string()),
            "user" => options.user = Some(values[0].to_string()),
            "port" => options.port = values[0].parse::<u16>().ok(),
            "identityfile" => options.identity_file = Some(values[0].to_string()),
            "include" => {
                flush_block(&mut names, &mut options, &mut elements);
                elements.push(Element::Include(
                    values.iter().map(|s| s.to_string()).collect(),
                ));
            }
            _ => {} // 그 외 지시(ServerAliveInterval 등)는 무시
        }
    }
    flush_block(&mut names, &mut options, &mut elements);
    elements
}

/// 현재 Host 블록을 항목으로 방출하고 옵션을 리셋한다.
/// `*`/`?`/`!`를 포함한 이름은 건너뛴다(literal 이름만 방출).
fn flush_block(
    names: &mut Option<Vec<String>>,
    options: &mut BlockOptions,
    elements: &mut Vec<Element>,
) {
    if let Some(block_names) = names.take() {
        let entries: Vec<HostEntry> = block_names
            .into_iter()
            .filter(|name| !name.contains(['*', '?', '!']))
            .map(|name| HostEntry {
                name,
                hostname: options.hostname.clone(),
                user: options.user.clone(),
                port: options.port,
                identity_file: options.identity_file.clone(),
            })
            .collect();
        if !entries.is_empty() {
            elements.push(Element::Hosts(entries));
        }
    }
    *options = BlockOptions::default();
}

/// 설정 파일을 재귀적으로 읽어 Host 항목을 등장 순서대로 모은다(Include 펼침).
fn parse_config_file(
    path: &Path,
    visited: &mut HashSet<PathBuf>,
) -> Result<Vec<HostEntry>, PortBridgeError> {
    // canonicalize는 존재 확인 + 정규화(cycle 검출 키)를 겸한다.
    let canonical = match path.canonicalize() {
        Ok(canonical) => canonical,
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return Err(PortBridgeError::SshConfigNotFound);
        }
        Err(error) => {
            return Err(PortBridgeError::SshConfigUnreadable {
                reason: error.to_string(),
            });
        }
    };
    if !visited.insert(canonical.clone()) {
        return Ok(Vec::new()); // 이미 방문 — Include cycle 차단
    }

    let content = std::fs::read_to_string(&canonical).map_err(|error| {
        PortBridgeError::SshConfigUnreadable {
            reason: error.to_string(),
        }
    })?;
    let base_dir = canonical
        .parent()
        .unwrap_or_else(|| Path::new(""))
        .to_path_buf();

    let mut entries = Vec::new();
    for element in parse_document(&content) {
        match element {
            Element::Hosts(hosts) => entries.extend(hosts),
            Element::Include(patterns) => {
                for pattern in patterns {
                    let included = resolve_include_path(&pattern, &base_dir);
                    // 누락/해석불가 Include는 비치명적 — 건너뛴다(ssh 관례: stale한 Include
                    // 한 줄이 그 앞에 정의된 무관한 alias까지 깨뜨리면 안 된다). 미지원
                    // tilde/glob 패턴도 literal 경로로 canonicalize 실패 → 여기서 흡수된다.
                    // 단, 존재하나 읽기 실패(권한/디렉터리)는 surfacing 위해 전파한다.
                    match parse_config_file(&included, visited) {
                        Ok(sub) => entries.extend(sub),
                        Err(PortBridgeError::SshConfigNotFound) => {}
                        Err(other) => return Err(other),
                    }
                }
            }
        }
    }
    Ok(entries)
}

/// Include 경로를 설정 파일 디렉터리 기준으로 해석한다(절대 경로는 그대로).
fn resolve_include_path(value: &str, base_dir: &Path) -> PathBuf {
    let path = Path::new(value);
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base_dir.join(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG_BASIC: &str = "\
Host prod
    HostName 10.0.0.1
    User ubuntu
    Port 2222

Host staging
    HostName 10.0.0.2
    User deploy
";

    const CONFIG_WILDCARD: &str = "\
Host *
    ServerAliveInterval 60

Host prod
    HostName 10.0.0.1

Host db1 db2 db3
    User postgres

Host !blocked
    HostName ignored
";

    /// parse_document 결과를 Host 항목으로 평탄화(Include 무시).
    fn host_entries(content: &str) -> Vec<HostEntry> {
        parse_document(content)
            .into_iter()
            .flat_map(|element| match element {
                Element::Hosts(hosts) => hosts,
                Element::Include(_) => Vec::new(),
            })
            .collect()
    }

    fn find<'a>(entries: &'a [HostEntry], name: &str) -> Option<&'a HostEntry> {
        entries.iter().find(|entry| entry.name == name)
    }

    // ── 순수 파싱 ──────────────────────────────────────────────────────────

    #[test]
    fn parses_host_options() {
        let entries = host_entries(CONFIG_BASIC);
        assert_eq!(entries.len(), 2); // prod + staging (Swift parity: hosts.count == 2)
        let prod = find(&entries, "prod").expect("prod");
        assert_eq!(prod.hostname.as_deref(), Some("10.0.0.1"));
        assert_eq!(prod.user.as_deref(), Some("ubuntu"));
        assert_eq!(prod.port, Some(2222));
    }

    #[test]
    fn omitted_port_is_none() {
        let entries = host_entries(CONFIG_BASIC);
        let staging = find(&entries, "staging").expect("staging");
        assert_eq!(staging.hostname.as_deref(), Some("10.0.0.2"));
        assert_eq!(staging.user.as_deref(), Some("deploy"));
        assert_eq!(staging.port, None);
    }

    #[test]
    fn skips_wildcard_negation_patterns() {
        let entries = host_entries(CONFIG_WILDCARD);
        // `Host *`와 `Host !blocked`는 방출되지 않는다.
        assert!(find(&entries, "*").is_none());
        assert!(find(&entries, "!blocked").is_none());
        // 따라서 prod의 hostname은 (뒤의 "ignored"가 아니라) 자기 블록 값이다.
        assert_eq!(
            find(&entries, "prod").unwrap().hostname.as_deref(),
            Some("10.0.0.1")
        );
    }

    #[test]
    fn multi_token_host_expands_to_each_name() {
        let entries = host_entries(CONFIG_WILDCARD);
        for name in ["db1", "db2", "db3"] {
            let entry = find(&entries, name).unwrap_or_else(|| panic!("{name}"));
            assert_eq!(entry.user.as_deref(), Some("postgres"));
        }
    }

    #[test]
    fn comments_and_blanks_ignored() {
        let content = "\
# leading comment
Host web   # trailing comment

    HostName 192.168.0.5
";
        let entries = host_entries(content);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, "web");
        assert_eq!(entries[0].hostname.as_deref(), Some("192.168.0.5"));
    }

    #[test]
    fn parses_identity_file() {
        let content = "\
Host gw
    HostName 10.0.0.9
    IdentityFile /home/me/.ssh/id_ed25519
";
        let entries = host_entries(content);
        assert_eq!(
            entries[0].identity_file.as_deref(),
            Some("/home/me/.ssh/id_ed25519")
        );
    }

    #[test]
    fn unknown_directive_in_literal_block_does_not_corrupt_options() {
        // literal 블록 안의 미지원 지시(ServerAliveInterval)는 무시되고, 그 뒤의
        // 알려진 지시(User)는 정상 유지돼야 한다(`_ => {}` arm이 블록을 깨지 않음).
        let content = "\
Host gw
    HostName 10.0.0.7
    ServerAliveInterval 60
    User admin
";
        let entries = host_entries(content);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].hostname.as_deref(), Some("10.0.0.7"));
        assert_eq!(entries[0].user.as_deref(), Some("admin"));
    }

    // ── 파일 해석 (임시 파일, std만) ────────────────────────────────────────

    /// 고유한 임시 디렉터리를 만든다(테스트 격리).
    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("pb_sshcfg_{}_{}", std::process::id(), tag));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test]
    fn resolve_host_returns_match() {
        let dir = temp_dir("match");
        let path = dir.join("config");
        std::fs::write(&path, CONFIG_BASIC).unwrap();

        let resolved = resolve_in_config(&path, "prod").unwrap().expect("prod");
        assert_eq!(
            resolved,
            ResolvedHost {
                hostname: Some("10.0.0.1".to_string()),
                user: Some("ubuntu".to_string()),
                port: Some(2222),
                identity_file: None,
            }
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_host_unknown_alias_is_none() {
        let dir = temp_dir("unknown");
        let path = dir.join("config");
        std::fs::write(&path, CONFIG_BASIC).unwrap();

        assert_eq!(resolve_in_config(&path, "nope").unwrap(), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_host_missing_file_is_not_found_error() {
        let dir = temp_dir("missing");
        let path = dir.join("does-not-exist");
        assert_eq!(
            resolve_in_config(&path, "prod"),
            Err(PortBridgeError::SshConfigNotFound)
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn include_directive_resolves_as_if_inline() {
        let dir = temp_dir("include");
        std::fs::write(
            dir.join("config"),
            "Host main\n    HostName 10.0.0.10\n\nInclude extra.txt\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("extra.txt"),
            "Host inc\n    HostName 9.9.9.9\n    User remote\n",
        )
        .unwrap();

        let resolved = resolve_in_config(&dir.join("config"), "inc")
            .unwrap()
            .expect("included host");
        assert_eq!(resolved.hostname.as_deref(), Some("9.9.9.9"));
        assert_eq!(resolved.user.as_deref(), Some("remote"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn include_cycle_terminates() {
        let dir = temp_dir("cycle");
        // a → b → a 순환. 무한 루프 없이 유한 종료해야 한다.
        std::fs::write(
            dir.join("config"),
            "Host a\n    HostName 1.1.1.1\nInclude b.txt\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("b.txt"),
            "Host b\n    HostName 2.2.2.2\nInclude config\n",
        )
        .unwrap();

        let a = resolve_in_config(&dir.join("config"), "a")
            .unwrap()
            .expect("a");
        assert_eq!(a.hostname.as_deref(), Some("1.1.1.1"));
        let b = resolve_in_config(&dir.join("config"), "b")
            .unwrap()
            .expect("b");
        assert_eq!(b.hostname.as_deref(), Some("2.2.2.2"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_include_target_is_non_fatal() {
        let dir = temp_dir("missinginc");
        // 존재하는 root + 누락 Include. Include 앞에 정의된 host는 여전히 해석돼야 한다.
        std::fs::write(
            dir.join("config"),
            "Host main\n    HostName 10.0.0.10\nInclude missing.txt\n",
        )
        .unwrap();
        let resolved = resolve_in_config(&dir.join("config"), "main")
            .unwrap()
            .expect("main resolves despite a missing include");
        assert_eq!(resolved.hostname.as_deref(), Some("10.0.0.10"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn unsupported_include_pattern_is_skipped() {
        let dir = temp_dir("unsupinc");
        // tilde/glob Include는 미지원 — literal 경로로 canonicalize 실패해 비치명적으로
        // 건너뛴다. root의 host는 영향받지 않아야 한다.
        std::fs::write(
            dir.join("config"),
            "Host main\n    HostName 1.2.3.4\nInclude ~/.ssh/x.conf\nInclude conf.d/*.conf\n",
        )
        .unwrap();
        let resolved = resolve_in_config(&dir.join("config"), "main")
            .unwrap()
            .expect("main resolves despite unsupported include patterns");
        assert_eq!(resolved.hostname.as_deref(), Some("1.2.3.4"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
