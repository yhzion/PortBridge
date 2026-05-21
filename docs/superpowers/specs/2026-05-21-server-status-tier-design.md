# 서버 상태 시각 위계 — 디자인 문서

- **작성일**: 2026-05-21
- **상태**: Draft → 구현 대기
- **범위**: `ServerSectionView` 상태 표현, `PortScanner` 오류 분류, `ServerScanState` 확장

## 1. 문제 정의

현재 PortBridge는 스캔 실패를 모두 같은 빨간 "danger" 처리로 표시한다.

```swift
case .error(let msg):
    Label(msg, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
```

이로 인해 두 가지 분리되어야 할 상태가 같은 시각 무게를 받는다:

1. **서버 오프라인** — 현재 `remoteCommandNotFound` 메시지가 빨간색으로 표시됨. SSH가 닿지 않는데 "ss 또는 lsof 명령이 필요합니다"라는 잘못된 안내가 나옴.
2. **원격 도구 부재** — `ss`/`lsof` 미설치가 빨간색으로 "오류"처럼 표시됨. 사용자 입장에서는 한 줄 명령으로 해결 가능한 환경 설정이지, 오류가 아님.

**근본 원인**: [PortScanner.swift:28-30](PortBridge/Scanning/PortScanner.swift:28)의 `result.stdout.isEmpty → remoteCommandNotFound` 휴리스틱이 오프라인과 도구 부재를 같은 케이스로 묶는다. 이후 view는 `PortBridgeError` 메시지를 그대로 빨강으로 표시하므로, 모든 환경적 문제가 "오류"로 보이게 됨.

목표: **상태를 의미에 맞는 시각 위계로 분리한다.** 오프라인은 상태, 도구 부재는 안내, 빨강은 진짜 오류 전용으로 환원한다.

## 2. 비목표 (Non-goals)

- 배포판 자동 감지 (uname / /etc/os-release 파싱) — 3개 명령 노출로 충분
- 오프라인 시 백그라운드 자동 재시도 — 사용자 명시 탭에 한정
- 마지막 성공 스캔 결과 캐싱·표시 — 오프라인 시 빈 본문 유지
- 인증 실패 UI 변경 — 기존 `AuthFailedView` 동작 유지 (단, 상태 점 노랑 추가)
- 다중 호스트 일괄 재시도

## 3. 결정된 시각 위계

| 티어 | 점 색 | 의미 | 본문 | 오류? |
|---|---|---|---|---|
| 회색 | `secondary.opacity(~0.5)` | 오프라인 (SSH 도달 실패) | 미렌더 | 아니오 |
| 노랑 | `.orange` | 도구 없음 (ss/lsof 미설치) | 설치 가이드 | 아니오 |
| 노랑 | `.orange` | 인증 실패 (기존) | `AuthFailedView` | 아니오 |
| 녹색 | `.green` | 온라인 | 포트 목록 | — |
| 빨강 | `.red` | 진짜 오류 (파싱 실패 등) | 한 줄 메시지 | 예 |
| (없음) | — | 미스캔(`.idle`) / 스캔중(`.scanning`) | 기존 동작 | — |

**색 일관성 원칙**: 노란 점은 "한 줄 명령 복사로 해결 가능한 환경 설정"을 의미한다. 인증 실패(`ssh-copy-id`)와 도구 부재(`apt install`)가 같은 시각 어휘를 공유함으로써 사용자는 "노란 점 = 복사할 게 있다"는 멘탈 모델을 학습한다.

## 4. 상태 모델 변경

### 4.1 `ServerScanState` 확장

```swift
enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case offline(isRetrying: Bool)   // NEW
    case toolMissing                 // NEW
    case authFailed(copyCommand: String)
    case error(String)
}
```

- `.offline(isRetrying:)` — `isRetrying`이 true일 때 상태 점이 펄스. 사용자 명시 탭으로만 진입.
- `.toolMissing` — SSH는 OK, 원격에 `ss`·`lsof` 모두 없음.
- `.error`는 진짜 예외(파싱 실패, 예상 외 throw)에만 사용.

### 4.2 `PortBridgeError` 정리

```swift
enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case serverUnreachable(host: String, reason: String)  // 통합: timeout/refused/no-route/dns/unreachable/down
    case remoteToolsMissing                                // 이름 변경: remoteCommandNotFound
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: UUID, stderr: String)
}
```

- `sshConnectTimeout` 케이스 제거 → `serverUnreachable`로 통합. 기존 `case .sshConnectTimeout`을 catch하던 곳 없음(grep으로 확인됨).
- `remoteCommandNotFound` → `remoteToolsMissing`으로 개명. 의미를 분명히 함.
- `errorDescription`은 `.serverUnreachable`·`.remoteToolsMissing` 경우 사용자에게 노출되지 않음(상태로 승격되어 view가 자체 본문 렌더). 디버그용으로만 채워둠.

### 4.3 `ServerSectionViewModel.scan()` 전이

```swift
func scan() async {
    if case .scanning = scanState { return }
    if case .offline(true) = scanState { return }   // 이미 재시도 중

    let wasOffline: Bool
    if case .offline = scanState { wasOffline = true } else { wasOffline = false }

    scanState = wasOffline ? .offline(isRetrying: true) : .scanning

    do {
        let loaded = try await scanner.scan(server: server)
        scanState = .loaded(loaded)
    } catch PortBridgeError.sshAuthFailed {
        scanState = .authFailed(copyCommand: "ssh-copy-id \(server.sshTarget)")
    } catch PortBridgeError.serverUnreachable {
        scanState = .offline(isRetrying: false)
    } catch PortBridgeError.remoteToolsMissing {
        scanState = .toolMissing
    } catch let error as PortBridgeError {
        scanState = .error(error.errorDescription ?? error.localizedDescription)
    } catch {
        scanState = .error(error.localizedDescription)
    }
}
```

**핵심**: 이전 상태가 `.offline`이면 `.scanning`을 거치지 않고 `.offline(isRetrying: true)`로 직접 전이. 헤더 ProgressView 노출을 회피하고 상태 점 펄스만으로 진행을 표현 ("조용한 재시도").

## 5. PortScanner 분류 보강

### 5.1 원격 명령에 명시적 도구 프로브 추가

현재:
```swift
let remoteCommand = "ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"
```

변경:
```swift
let remoteCommand = """
if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
  echo PORTBRIDGE_TOOLS_MISSING >&2
  exit 127
fi
ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
"""
```

**왜 명시 프로브인가**: 현재 `stdout.isEmpty` 휴리스틱은 다음 경우들을 구별 못함:
- 진짜 도구 부재
- 모든 포트가 비표시 범위(권한 부족으로 lsof가 일부만 출력)
- 셸 자체가 다른 stderr 메시지 출력

`command -v`는 POSIX 표준이고 exit code 127은 "command not found" 관용. 별도 마커 문자열로 이중 안전망.

### 5.2 분류 우선순위

```swift
if result.exitCode != 0 {
    let stderr = result.stderr.lowercased()

    // 1. 인증 실패 (기존)
    if stderr.contains("permission denied") || stderr.contains("publickey") {
        throw PortBridgeError.sshAuthFailed(host: server.host)
    }

    // 2. 도달 불가 패턴 (NEW — 통합)
    let unreachablePatterns = [
        "connection timed out", "connect timeout",
        "no route to host",
        "connection refused",
        "could not resolve hostname", "name or service not known",
        "network is unreachable",
        "host is down",
    ]
    if unreachablePatterns.contains(where: { stderr.contains($0) }) {
        throw PortBridgeError.serverUnreachable(host: server.host, reason: stderr)
    }

    // 3. 도구 부재 (NEW — 명시 프로브)
    if result.exitCode == 127 || stderr.contains("portbridge_tools_missing") {
        throw PortBridgeError.remoteToolsMissing
    }
}

// 4. 파싱 (성공이지만 출력이 이상한 경우)
//    → 기존대로 진행, 파서가 빈 결과를 돌려주면 .loaded([])
//    실제 throw는 ScanOutputParser에서.
```

**제거**: 기존 `if result.stdout.isEmpty { throw .remoteCommandNotFound }` 분기 완전 삭제. 도구 부재는 명시 프로브로만 판단.

## 6. View 동작 사양

### 6.1 `.offline(isRetrying:)`

| 요소 | 동작 |
|---|---|
| chevron | **렌더 안 함** — 12px 빈 공간 유지 |
| ↻ 버튼 | **숨김** |
| ⋯ 메뉴 | 정상 (편집/삭제) |
| 모노그램 | `opacity: 0.55` |
| primary 텍스트 | `.foregroundStyle(.secondary)` |
| 상태 점 | 회색 (`secondary.opacity(0.5)`), `isRetrying`이면 펄스 |
| Body | **미렌더** (isExpanded 무시) |
| Row 탭 | `Task { await section.scan() }` |
| 호버 | 옅은 background tint |

**펄스 애니메이션**: `opacity 0.4 ↔ 1.0`, `scale 0.9 ↔ 1.0`, ease-in-out, 1.4s 무한 반복. `.offline(isRetrying: true)`인 동안만.

### 6.2 `.toolMissing`

| 요소 | 동작 |
|---|---|
| chevron | 정상 |
| ↻ 버튼 | 정상 |
| 모노그램 | 정상 |
| 상태 점 | 노랑 (`.orange`) |
| Body | 새 `ToolInstallGuideView` |
| Row 탭 | `toggleExpanded()` |
| 첫 진입 | 자동 펼침. 이후엔 사용자 선호 보존. |

### 6.3 `.authFailed` (기존, 보강)

- 헤더·본문 레이아웃 기존 유지.
- **추가 1**: 상태 점 노랑(`.orange`) 표시. 도구 부재와 시각 어휘 통일.
- **추가 2**: `AuthFailedView` 내부의 `"복사" / "복사됨 ✓"` 텍스트 버튼을 §7.1의 아이콘 + 체크 패턴으로 마이그레이션. 두 노란 티어 본문이 동일 복사 UX를 공유.

### 6.4 `.loaded`

- 상태 점 녹색 (`.green`).
- 기타 기존 동작 유지.

### 6.5 `.error`

- 상태 점 없음 (드문 케이스, 본문 메시지로 충분).
- 본문 빨강 + `exclamationmark.triangle`.
- 기존 동작 유지.

### 6.6 `.idle` / `.scanning`

- 점 없음, 기존 동작 유지.

## 7. 새 컴포넌트: `ToolInstallGuideView`

`AuthFailedView`와 같은 패턴의 노란-티어 인스트럭션 뷰.

```swift
private struct ToolInstallGuideView: View {
    let onRetry: () -> Void

    private let commands: [(distro: String, command: String)] = [
        ("Debian / Ubuntu", "sudo apt install iproute2 lsof"),
        ("RHEL / CentOS",   "sudo yum install iproute lsof"),
        ("Alpine",          "apk add iproute2 lsof"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("원격 서버에 ss 또는 lsof가 필요합니다",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("포트 목록을 조회하려면 둘 중 하나가 설치되어 있어야 합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(commands, id: \.distro) { item in
                InstallCommandRow(distro: item.distro, command: item.command)
            }
        }
        .padding(.vertical, 6)
    }
}
```

### 7.1 `InstallCommandRow` — 복사 버튼

```swift
private struct InstallCommandRow: View {
    let distro: String
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(distro)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(copied ? "복사됨" : "복사")
            .accessibilityLabel(copied ? "복사됨" : "명령 복사")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            copied = false
        }
    }
}
```

**복사 버튼 사양**:
- 아이콘: `doc.on.doc` (SF Symbol) → `checkmark`.
- 색: idle은 `.secondary`(주변 폰트 톤), copied는 `.green`.
- 호버 시 `.primary` 색으로 진해짐 (SwiftUI `.onHover`로 구현).
- 아이콘 전환은 `.contentTransition(.symbolEffect(.replace))`로 macOS 14+ 네이티브 SF Symbol 모핑 사용. chevron 무애니메이션 결정(§8)과 무관 — 이쪽은 명시적 피드백이 필요한 케이스.
- 1.8초 자동 복귀.
- 기존 [AuthFailedView](PortBridge/Views/ServerSectionView.swift:209)의 `"복사" / "복사됨 ✓"` 텍스트 버튼도 동일 아이콘 패턴으로 마이그레이션 (일관성).

## 8. chevron 무애니메이션

현재 [ServerSectionView.swift:80](PortBridge/Views/ServerSectionView.swift:80)의 `toggleExpandedAnimated`는 `withAnimation(.spring)`으로 chevron rotation과 body expand를 함께 애니메이트한다. chevron만 즉시 교체로 변경:

```swift
Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(width: 12)
    .transaction { $0.animation = nil }   // ← 추가
```

`.transaction { $0.animation = nil }`은 부모 `withAnimation` 스코프 안에서도 이 view만 애니메이션을 비활성화한다. body의 spring 펼침은 그대로 보존됨.

## 9. 상태 점 컴포넌트

모노그램 우하단에 8px 점. `ServerMonogram`에 옵션 추가:

```swift
enum ServerStatusDot: Equatable {
    case none
    case offline(pulse: Bool)
    case warning   // 노랑 — toolMissing / authFailed
    case online    // 녹색

    var fill: Color? { ... }
}

private struct ServerMonogram: View {
    let server: Server
    var status: ServerStatusDot = .none
    var dimmed: Bool = false
    // ... 기존 본체에 상태 점 ZStack overlay 추가
}
```

- 점은 모노그램 직사각형 우하단에서 2px 바깥쪽으로 떠 있음.
- 1.5px 패널색 외곽선으로 둘러싸 모노그램과 겹쳐도 분리되어 보임.
- 펄스는 회색일 때만(`isRetrying` true).

## 10. 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `Models/PortBridgeError.swift` | `sshConnectTimeout` 제거, `serverUnreachable` 추가, `remoteCommandNotFound` → `remoteToolsMissing` 개명 |
| `ViewModels/ServerSectionViewModel.swift` | `.offline` / `.toolMissing` 상태 추가, `scan()` 분기 보강 |
| `Scanning/PortScanner.swift` | 원격 명령에 도구 프로브 추가, stderr 패턴 매칭 보강, `stdout.isEmpty` 휴리스틱 제거 |
| `Views/ServerSectionView.swift` | 상태별 헤더/본문 분기, chevron `.transaction` 무애니메이션, `ServerMonogram`에 status dot 통합 |
| `Views/ServerSectionView.swift` | `AuthFailedView` 복사 버튼을 아이콘 + 체크 패턴으로 마이그레이션 |
| `Views/ServerSectionView.swift` (또는 신규 파일) | `ToolInstallGuideView`, `InstallCommandRow` 추가 |

## 11. 테스트 영향

| 테스트 | 영향 |
|---|---|
| `PortBridgeErrorTests` | `remoteCommandNotFound` 케이스 삭제, `serverUnreachable` / `remoteToolsMissing` 추가 |
| `PortScannerTests` | 새 stderr 패턴 분류 케이스 (no-route/refused/dns/unreachable) 추가, 도구 프로브 프로토콜 검증 |
| `ServerSectionViewModelTests` | 오프라인→재시도 전이가 `.scanning`을 거치지 않고 `.offline(isRetrying: true)`로 가는지 검증 |
| `MockCommandRunner` | 새 stderr 시나리오 fixture 추가 |

## 12. 시안

HTML 시안: `/tmp/portbridge-offline-mockup.html` (브라우저에서 확인 가능, 복사 버튼 동작 포함).
