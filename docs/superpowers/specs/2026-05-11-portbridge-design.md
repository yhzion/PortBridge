# PortBridge — Design Spec

- **Date**: 2026-05-11
- **Status**: Approved (브레인스토밍 완료, 구현 계획 작성 대기)
- **Source**: `/tmp/handoff.md` (요구사항 핸드오프)

## 1. 개요

**PortBridge**는 macOS SwiftUI 기반 GUI 앱으로, `~/.ssh/config`에 등록된 리모트 서버의 리스닝 TCP 포트를 조회하고 선택적으로 로컬 포트 포워딩(`ssh -L`)을 토글할 수 있는 도구이다.

핵심 가치 제안:
- 시스템 `ssh` 바이너리를 그대로 사용 → SSH 키·known_hosts·config를 OS와 공유, 외부 SSH 라이브러리 의존 없음.
- 포워딩마다 독립 `Process` → 토글 라이프사이클이 단순(`terminate()`로 끝남).

## 2. 결정 사항 (Decisions)

| 항목 | 선택 | 이유 |
|---|---|---|
| SSH 호스트 발견 | 직접 파싱 + 와일드카드 제외 + `Include` 재귀 | 외부 의존 없음, 단순. `ssh -G`는 enumerate 불가. |
| 포트 스캔 명령 | `ss -tlnH` 우선, 실패 시 `lsof -iTCP -sTCP:LISTEN` 폴백 | 호환성 + 권장 표준 모두 커버. 프로세스 이름은 best-effort. |
| 로컬 포트 충돌 | 기본은 동일 번호, 충돌 시 다른 로컬 포트 입력 시트 | 명시적·예측 가능, 자동 할당은 어디로 갔는지 모호. |
| 영속성 | 없음 (MVP) | 구현 단순, 버그 표면 적음. |
| 빌드 시스템 | Xcode 프로젝트 (`.xcodeproj`) 단일 앱 타겟 | macOS GUI 앱 표준 경로. |
| 모듈 분리 | 단일 타겟, 폴더 분리 + protocol 경계 | MVP 규모에 적합. SPM 패키지 분리는 과잉. |
| App Sandbox | OFF | 외부 `ssh` 프로세스 호출 자유 확보. 개인 도구 용도. |
| 최소 macOS 타겟 | macOS 14 (Sonoma) | `@Observable` 등 신 API 활용 가능. |
| 테스트 범위 | 파서·스캐너 단위 테스트만 (XCTest) | 통합 영역(Process, 네트워크)은 수동 QA. |

## 3. 디렉토리 & 모듈 구조

```
PortBridge/
├── PortBridge.xcodeproj/
├── PortBridge/                   # 앱 타겟 소스
│   ├── PortBridgeApp.swift       # @main App entry + applicationWillTerminate
│   ├── Models/
│   │   ├── SSHHost.swift
│   │   ├── RemotePort.swift
│   │   └── Forwarding.swift
│   ├── SSH/
│   │   ├── SSHConfigParser.swift
│   │   └── CommandRunner.swift   # protocol + ProcessCommandRunner
│   ├── Scanning/
│   │   ├── PortScanner.swift
│   │   └── ScanOutputParser.swift
│   ├── Tunneling/
│   │   └── TunnelManager.swift
│   ├── ViewModels/
│   │   └── AppViewModel.swift    # @MainActor @Observable
│   └── Views/
│       ├── ContentView.swift
│       ├── HostPickerView.swift
│       ├── PortListView.swift
│       └── ForwardingRowView.swift
└── PortBridgeTests/
    ├── SSHConfigParserTests.swift
    ├── ScanOutputParserTests.swift
    ├── PortScannerTests.swift
    └── Fixtures/
        ├── config_basic.txt
        ├── config_wildcard.txt
        ├── config_include.txt
        ├── config.d/extra.txt
        ├── ss_ipv4_only.txt
        ├── ss_ipv6_mixed.txt
        ├── ss_no_header.txt
        ├── lsof_typical.txt
        └── lsof_no_process.txt
```

## 4. 핵심 컴포넌트

### 4.1 `SSHConfigParser`

```swift
struct SSHHost: Identifiable, Hashable {
    var id: String { name }
    let name: String          // "Host" 라인의 값
    let hostName: String?     // HostName 옵션
    let user: String?
    let port: Int?
}

enum SSHConfigParser {
    static func parse(
        path: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".ssh/config")
    ) throws -> [SSHHost]
}
```

- 라인 단위 스캔. `Host` 키워드로 블록 시작. 같은 블록 안에서 `HostName`/`User`/`Port` 수집.
- `Include`: 글롭 확장 후 재귀. 방문 경로를 `Set<URL>`로 추적해 무한 루프 방지.
- 와일드카드(`*`, `?`, `!`) 포함 `Host` 값은 결과에서 제외.
- 공백 분리된 다중 호스트(`Host a b c`)는 각각 등록.

### 4.2 `CommandRunner`

```swift
struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult
}

final class ProcessCommandRunner: CommandRunner { ... }
```

- 타임아웃: `ss` 등 빠른 호출은 5초, ssh 첫 연결은 15초.
- stdout/stderr 별도 Pipe로 읽기. stderr는 ring buffer로 마지막 4KB만 유지.

### 4.3 `PortScanner`

```swift
struct RemotePort: Identifiable, Hashable {
    var id: String { "\(address):\(port)" }
    let port: Int
    let address: String       // "0.0.0.0", "127.0.0.1", "::"
    let processName: String?
}

struct PortScanner {
    let runner: CommandRunner
    func scan(host: String, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort]
}
```

- 명령: `ssh -o BatchMode=yes -o ConnectTimeout=10 <host> "ss -tlnH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"`
- `BatchMode=yes`: 비밀번호 프롬프트 차단. 키 인증 실패 시 즉시 실패.
- 출력의 첫 줄 형태로 ss/lsof 형식을 자동 판별.
- 범위 필터(`range`) 적용, `Set` 기반 중복 제거.

### 4.4 `TunnelManager`

```swift
@MainActor
final class TunnelManager {
    private(set) var active: [Forwarding.ID: ActiveTunnel] = [:]
    func start(host: String, remotePort: Int, localPort: Int) async throws -> Forwarding
    func stop(_ id: Forwarding.ID)
    func shutdownAll()
}

private struct ActiveTunnel {
    let process: Process
    let forwarding: Forwarding
    var monitorTask: Task<Void, Never>?
}
```

시작 명령:

```
ssh -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o BatchMode=yes \
    -L <localPort>:localhost:<remotePort> \
    <host>
```

- 시작 후 ~2초 살아있고 stderr에 fatal 메시지가 없으면 `active`에 등록.
- 각 터널마다 `Task`로 `process.waitUntilExit()` 감시 → 죽으면 매니저/ViewModel에 통보.
- `stop`: `terminate()` (SIGTERM). 1초 후에도 살아있으면 강제 종료.
- `shutdownAll`: 앱 종료 훅에서 동기적으로 모든 활성 터널 종료.

### 4.5 `AppViewModel`

```swift
@MainActor
@Observable
final class AppViewModel {
    var hosts: [SSHHost] = []
    var selectedHost: SSHHost?
    var ports: [RemotePort] = []
    var searchText: String = ""
    var forwardings: [Forwarding] = []
    var isScanning = false
    var lastError: String?
    var pendingPortConflict: PortConflict?

    var filteredPorts: [RemotePort] { /* searchText 필터 */ }

    func loadHosts() async
    func scan() async
    func toggleForwarding(for port: RemotePort) async
}
```

- `Forwarding`: `id`, `host`, `remotePort`, `localPort`, `state (idle / starting / active / error)`.
- `PortConflict`: 시트로 띄울 충돌 정보(원하던 로컬 포트, 호스트, 리모트 포트).

## 5. 데이터 흐름

```
앱 실행 → loadHosts() → SSHConfigParser.parse() → hosts → HostPickerView

호스트 선택 + 스캔 클릭 → AppViewModel.scan()
    → PortScanner.scan(host:) → CommandRunner.run("ssh", [...])
    → ScanOutputParser → ports → PortListView (검색 필터)

토글 ON → toggleForwarding(port:)
    → TunnelManager.start(host, remotePort, localPort)
    ├─ 성공: forwardings에 .active 추가, 모니터 Task 시작
    └─ 실패 (bind / auth / ExitOnForwardFailure):
       → AppViewModel.pendingPortConflict 세팅
       → 사용자 새 포트 입력 시트 → 재시도

토글 OFF / 앱 종료
    → TunnelManager.stop(id) / shutdownAll()
    → process.terminate()
    → forwardings 정리
```

## 6. 에러 처리

```swift
enum PortBridgeError: LocalizedError {
    case sshConfigNotFound
    case sshConfigUnreadable(Error)
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)
    case remoteCommandNotFound
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: Forwarding.ID, stderr: String)
}
```

| 상황 | UI |
|---|---|
| ssh config 없음 | 호스트 드롭다운 자리에 안내 메시지 |
| 인증 실패 / 타임아웃 | 포트 리스트 자리에 에러 배너 + "재시도" |
| ss/lsof 둘 다 없음 | "리모트에 ss/lsof가 없습니다" 메시지 |
| 로컬 포트 충돌 | 모달 시트, 새 로컬 포트 입력 |
| 포워딩 도중 자살 | 행이 🔴 ⚠ 로 전환, 호버 시 stderr 일부, "다시 연결" |
| 일반 예외 | 하단 토스트(`lastError`), 5초 후 자동 dismiss |

- stderr는 항상 Pipe로 캡처, 마지막 4KB만 보관(ring buffer).
- 사용자에게는 마지막 1~3줄 노출, "상세 보기"로 전체.
- 행 상태 아이콘: 🟢 active / 🟡 starting / 🔴 error / ⚪️ idle.

## 7. 테스트 전략

### 7.1 단위 테스트 (XCTest)

| 대상 | 검증 |
|---|---|
| `SSHConfigParser` | 호스트 목록, 와일드카드 제외, Include 재귀, 옵션 상속 |
| `ScanOutputParser.parseSS` | IPv4/IPv6/dual-stack, 헤더 유무 |
| `ScanOutputParser.parseLsof` | 일반 케이스, 권한 없는 케이스(프로세스 이름 누락) |
| `PortScanner` (MockCommandRunner) | ss 성공, ss 실패→lsof 성공, 둘 다 실패 |
| 검색 필터 로직 | 포트 번호·프로세스 이름 매칭 |

### 7.2 명시적 비대상

| 항목 | 사유 |
|---|---|
| 실제 `ssh` 호출 | 환경 의존, CI 불안정 |
| `TunnelManager`의 Process 라이프사이클 | 통합 영역, 수동 QA로 검증 |
| SwiftUI 뷰 렌더링 | 외부 의존(ViewInspector) 도입은 핸드오프 정신 위배 |

### 7.3 수동 QA 체크리스트

- [ ] ssh config의 호스트가 드롭다운에 나타남, 와일드카드 엔트리는 제외
- [ ] 잘못된 호스트 선택 시 명확한 에러 표시
- [ ] 정상 호스트 스캔 시 포트가 표시됨
- [ ] 검색어 입력 시 즉시 필터링
- [ ] 토글 ON → `ps aux | grep "ssh -N -L"` 로 프로세스 확인, 로컬 포트로 실제 접속 가능
- [ ] 토글 OFF → 1초 안에 SSH 프로세스 종료
- [ ] 로컬 포트 점유 상태에서 토글 → 다이얼로그가 뜨고 다른 포트로 성공
- [ ] 앱 ⌘Q 종료 → 모든 SSH 프로세스 종료 (좀비 없음)
- [ ] 리모트 서버 일시 다운 → 약 45초 내 행 상태가 🔴 에러로 전환

## 8. 의도적으로 범위 밖 (Non-Goals)

- 포워딩 상태 영속성, 자동 재연결.
- ssh config의 `Match` 블록 지원.
- 비밀번호 프롬프트, 다단계 인증(BatchMode=yes로 차단).
- 메뉴바 아이콘, 시스템 트레이.
- Mac App Store 배포 (Sandbox OFF).
- UDP 포트, 비-`localhost` 바인드.

## 9. 다음 단계

이 설계 승인 후 `writing-plans` 스킬로 구현 계획(`plan.md`)을 작성한다.
