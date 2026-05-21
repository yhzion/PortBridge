# 서버 상태 시각 위계 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스캔 실패를 의미별 세 티어(회색 오프라인 · 노랑 도구부재/인증실패 · 빨강 진짜오류)로 분리하고, 오프라인은 조용한 재시도, 도구부재는 설치 안내 UI로 표시한다.

**Architecture:** `PortScanner`가 stderr 패턴 + 명시 도구 프로브로 오류를 정확히 분류 → `PortBridgeError`의 새 케이스로 throw → `ServerSectionViewModel`이 캐치해 `ServerScanState`의 새 상태(`.offline` / `.toolMissing`)로 매핑 → `ServerSectionView`가 상태별 UI를 렌더한다. 모노그램에 상태 점, 새 `ToolInstallGuideView`로 설치 명령 노출.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14.0+), XCTest, SF Symbols (`doc.on.doc`, `checkmark`, `chevron.down/right`), `.contentTransition(.symbolEffect(.replace))`.

**Spec:** [docs/superpowers/specs/2026-05-21-server-status-tier-design.md](../specs/2026-05-21-server-status-tier-design.md)

---

## File Structure

| 파일 | 책임 | 작업 종류 |
|---|---|---|
| `PortBridge/Models/PortBridgeError.swift` | 오류 분류 enum | 케이스 추가/제거 |
| `PortBridge/ViewModels/ServerSectionViewModel.swift` | 스캔 상태 머신 | 상태 추가, scan() 분기 보강 |
| `PortBridge/Scanning/PortScanner.swift` | 원격 명령 실행 + stderr 분류 | 도구 프로브 + 패턴 매칭 보강 |
| `PortBridge/Views/ServerSectionView.swift` | 섹션 UI 분기 + 모노그램 + 인스톨 가이드 + 인증 실패 뷰 | 상태별 분기, 새 컴포넌트 추가, 기존 컴포넌트 보강 |
| `PortBridgeTests/PortBridgeErrorTests.swift` | 오류 케이스 테스트 | 케이스 추가/제거 |
| `PortBridgeTests/PortScannerTests.swift` | 스캐너 분류 테스트 | 새 stderr 시나리오 추가 |
| `PortBridgeTests/ServerSectionViewModelTests.swift` | ViewModel 상태 전이 테스트 | 새 매핑 검증, 기존 테스트 명칭 갱신 |

ServerSectionView.swift는 이미 여러 private View(`ServerMonogram`, `AuthFailedView`)를 포함하고 있어 새 컴포넌트(`ToolInstallGuideView`, `InstallCommandRow`)도 같은 파일에 추가한다 — 응집도 유지, 모듈 분할은 YAGNI.

---

## Task 1: PortBridgeError에 새 케이스 추가 (호환 유지)

**Files:**
- Modify: `PortBridge/Models/PortBridgeError.swift`
- Test: `PortBridgeTests/PortBridgeErrorTests.swift`

기존 케이스(`.sshConnectTimeout`, `.remoteCommandNotFound`)는 일단 유지 — Task 11에서 제거. 이번 단계는 새 케이스만 추가해 컴파일/테스트 그린 유지.

- [ ] **Step 1: Write failing tests**

`PortBridgeTests/PortBridgeErrorTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class PortBridgeErrorTests: XCTestCase {
    func test_sshAuthFailed_includesHost() {
        let err = PortBridgeError.sshAuthFailed(host: "prod")
        XCTAssertTrue(err.errorDescription?.contains("prod") ?? false)
    }

    func test_serverUnreachable_includesHost() {
        let err = PortBridgeError.serverUnreachable(host: "prod-api", reason: "no route to host")
        XCTAssertTrue(err.errorDescription?.contains("prod-api") ?? false)
    }

    func test_remoteToolsMissing_hasDescription() {
        let err = PortBridgeError.remoteToolsMissing
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortBridgeErrorTests 2>&1 | tail -30
```

Expected: 두 새 테스트가 컴파일 오류로 실패 — `serverUnreachable` / `remoteToolsMissing` 케이스 없음.

- [ ] **Step 3: Add new cases**

`PortBridge/Models/PortBridgeError.swift` 전체:

```swift
import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)           // 유지 (Task 11에서 제거)
    case serverUnreachable(host: String, reason: String)  // NEW
    case remoteCommandNotFound                      // 유지 (Task 11에서 제거)
    case remoteToolsMissing                         // NEW
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: UUID, stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .sshConnectTimeout(let host):
            return "\(host) 연결 타임아웃."
        case .serverUnreachable(let host, _):
            return "\(host) 서버에 연결할 수 없습니다."
        case .remoteCommandNotFound:
            return "원격 서버에서 열린 포트 목록을 가져올 수 없습니다. (ss 또는 lsof 명령이 필요합니다)"
        case .remoteToolsMissing:
            return "원격 서버에 ss 또는 lsof가 필요합니다."
        case .scanOutputUnparseable(let preview):
            return "스캔 출력 파싱 실패: \(preview)"
        case .localPortInUse(let port):
            return "로컬 포트 \(port)이(가) 이미 사용 중입니다."
        case .forwardingDiedEarly(let stderr):
            return "포워딩이 즉시 종료되었습니다: \(stderr)"
        case .tunnelCrashed(_, let stderr):
            return "터널이 끊겼습니다: \(stderr)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortBridgeErrorTests 2>&1 | tail -30
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortBridge/Models/PortBridgeError.swift PortBridgeTests/PortBridgeErrorTests.swift
git commit -m "feat(error): add serverUnreachable and remoteToolsMissing cases

오프라인과 도구 부재를 분리된 오류 케이스로 모델링. 기존
sshConnectTimeout / remoteCommandNotFound는 마이그레이션 후 제거 예정.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: ServerScanState에 새 케이스 추가 + View에 stub 핸들러

**Files:**
- Modify: `PortBridge/ViewModels/ServerSectionViewModel.swift`
- Modify: `PortBridge/Views/ServerSectionView.swift` (switch 분기 stub)

스테이트 추가 시 ServerSectionView의 switch가 non-exhaustive로 경고 발생. 빈 핸들러 stub을 함께 추가해 컴파일 그린 유지. 실제 UI는 Task 9–11에서 채움.

- [ ] **Step 1: Add new state cases**

`PortBridge/ViewModels/ServerSectionViewModel.swift` 상단의 enum:

```swift
enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case offline(isRetrying: Bool)            // NEW
    case toolMissing                           // NEW
    case error(String)
    case authFailed(copyCommand: String)
}
```

- [ ] **Step 2: Add stub branches in ServerSectionView**

`PortBridge/Views/ServerSectionView.swift`의 `sectionContent` switch에 두 케이스 추가 (`.authFailed` 위에):

```swift
case .offline:
    EmptyView()

case .toolMissing:
    EmptyView()
```

전체 switch는 다음 형태가 된다:

```swift
switch section.scanState {
case .idle: ...
case .scanning: ...
case .loaded where inactivePorts.isEmpty: ...
case .loaded: ...
case .offline:
    EmptyView()
case .toolMissing:
    EmptyView()
case .error(let msg): ...
case .authFailed(let cmd): ...
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: Build succeeds, no warnings about non-exhaustive switch.

- [ ] **Step 4: Run all existing tests**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: All existing tests still pass (no behavior change yet).

- [ ] **Step 5: Commit**

```bash
git add PortBridge/ViewModels/ServerSectionViewModel.swift PortBridge/Views/ServerSectionView.swift
git commit -m "feat(state): add offline and toolMissing scan states

뷰는 빈 핸들러로 stub. 실제 UI는 후속 태스크에서 채움.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: PortScanner — 도구 프로브 + serverUnreachable 분류

**Files:**
- Modify: `PortBridge/Scanning/PortScanner.swift`
- Test: `PortBridgeTests/PortScannerTests.swift`

stderr 패턴을 6종으로 확장해 `.serverUnreachable` 던지기. 원격 명령에 명시 도구 프로브 추가 (Task 4에서 사용). `stdout.isEmpty → remoteCommandNotFound` 휴리스틱은 Task 4에서 제거.

- [ ] **Step 1: Write failing tests for unreachable patterns**

`PortBridgeTests/PortScannerTests.swift`의 `test_authFailedStderr_throwsAuthError` 아래에 추가:

```swift
func test_connectionTimedOut_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Connection timed out")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable(let host, _) = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
        XCTAssertEqual(host, "prod")
    }
}

func test_noRouteToHost_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host 10.0.0.1 port 22: No route to host")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
    }
}

func test_connectionRefused_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Connection refused")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
    }
}

func test_couldNotResolveHostname_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: Could not resolve hostname prod: Name or service not known")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
    }
}

func test_networkUnreachable_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Network is unreachable")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
    }
}

func test_hostIsDown_throwsServerUnreachable() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: Host is down")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        guard case .serverUnreachable = error else {
            XCTFail("expected .serverUnreachable, got \(error)"); return
        }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortScannerTests 2>&1 | tail -30
```

Expected: 6 new tests fail (현재는 stderr에 timed out만 인식하고 그 외엔 `remoteCommandNotFound`나 success로 빠짐).

- [ ] **Step 3: Update PortScanner with new classification**

`PortBridge/Scanning/PortScanner.swift`의 `scan()` 메서드:

```swift
func scan(server: Server, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
    let remoteCommand = """
    if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
      echo PORTBRIDGE_TOOLS_MISSING >&2
      exit 127
    fi
    ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
    """
    let args = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-p", "\(server.port)",
        server.sshTarget,
        remoteCommand
    ]

    let result = try await runner.run(sshExecutable, args: args, timeout: 15)

    if result.exitCode != 0 {
        let stderr = result.stderr.lowercased()

        // 1. 인증 실패 (최우선)
        if stderr.contains("permission denied") || stderr.contains("publickey") {
            throw PortBridgeError.sshAuthFailed(host: server.host)
        }

        // 2. 도달 불가 패턴 통합 (timeout 포함)
        let unreachablePatterns = [
            "connection timed out", "connect timeout",
            "no route to host",
            "connection refused",
            "could not resolve hostname", "name or service not known",
            "network is unreachable",
            "host is down",
        ]
        if unreachablePatterns.contains(where: { stderr.contains($0) }) {
            throw PortBridgeError.serverUnreachable(host: server.host, reason: result.stderr)
        }

        // Task 4에서 추가: 도구 부재 분기
    }

    let first = result.stdout.components(separatedBy: .newlines).first ?? ""
    let parsed: [RemotePort]
    if first.uppercased().hasPrefix("LISTEN") || first.contains("State") {
        parsed = ScanOutputParser.parseSS(result.stdout)
    } else {
        parsed = ScanOutputParser.parseLsof(result.stdout)
    }

    let deduped = Self.deduplicateSamePort(parsed)
    return deduped
        .filter { range.contains($0.port) }
        .sorted { $0.port < $1.port }
}
```

**중요**: 기존 `sshConnectTimeout` throw는 제거 — `connection timed out` 패턴이 `unreachablePatterns`에 포함되어 `.serverUnreachable`로 throw됨. 기존 `stdout.isEmpty → remoteCommandNotFound` 분기는 다음 태스크(Task 4)까지 남겨둔다.

잠시: 기존 코드의 `if result.stdout.isEmpty { throw PortBridgeError.remoteCommandNotFound }`는 그대로 유지. 이번 단계에서는 stderr 매칭만 보강.

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortScannerTests 2>&1 | tail -30
```

Expected: 6 new tests pass + 모든 기존 PortScanner 테스트 pass.

- [ ] **Step 5: Commit**

```bash
git add PortBridge/Scanning/PortScanner.swift PortBridgeTests/PortScannerTests.swift
git commit -m "feat(scanner): classify all unreachable patterns as serverUnreachable

connection timed out · no route to host · connection refused · DNS 실패 ·
network is unreachable · host is down — 6종 stderr 패턴을 .serverUnreachable로
통합 throw. 원격 명령에 도구 프로브 추가 (Task 4에서 활용).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: PortScanner — remoteToolsMissing 분류

**Files:**
- Modify: `PortBridge/Scanning/PortScanner.swift`
- Test: `PortBridgeTests/PortScannerTests.swift`

Task 3에서 추가한 도구 프로브가 exit code 127 + `PORTBRIDGE_TOOLS_MISSING` 마커를 stderr로 출력. 이 신호를 `.remoteToolsMissing`으로 throw. 기존 `stdout.isEmpty → remoteCommandNotFound` 휴리스틱 제거.

- [ ] **Step 1: Write failing tests**

`PortBridgeTests/PortScannerTests.swift`에 추가:

```swift
func test_toolsMissingMarker_throwsRemoteToolsMissing() async throws {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 127, stdout: "", stderr: "PORTBRIDGE_TOOLS_MISSING\n")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        XCTAssertEqual(error, .remoteToolsMissing)
    }
}

func test_exit127WithoutMarker_throwsRemoteToolsMissing() async throws {
    // 일부 셸은 stderr 출력 없이 127만 반환 — fallback으로도 잡혀야 함.
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 127, stdout: "", stderr: "")
    ]
    let scanner = PortScanner(runner: mock)
    do {
        _ = try await scanner.scan(server: makeServer())
        XCTFail("expected throw")
    } catch let error as PortBridgeError {
        XCTAssertEqual(error, .remoteToolsMissing)
    }
}

func test_emptyStdoutWithoutErrorSignal_returnsEmptyArray() async throws {
    // 도구 부재가 아니라 단순히 listening 포트가 없는 경우 — 빈 배열 반환.
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 0, stdout: "", stderr: "")
    ]
    let scanner = PortScanner(runner: mock)
    let ports = try await scanner.scan(server: makeServer())
    XCTAssertEqual(ports.count, 0)
}
```

`test_emptyStdoutWithoutErrorSignal_returnsEmptyArray`는 기존 휴리스틱 제거의 부산물 — 이전엔 빈 stdout이 `.remoteCommandNotFound`로 throw 됐었지만, 이제는 정상적으로 빈 결과를 반환해야 한다.

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortScannerTests 2>&1 | tail -30
```

Expected: 3 new tests fail.

- [ ] **Step 3: Update PortScanner**

`PortBridge/Scanning/PortScanner.swift`의 `scan()` 내부 `if result.exitCode != 0 { ... }` 블록 끝부분 (Task 3에서 추가한 unreachable 분기 뒤):

```swift
        if unreachablePatterns.contains(where: { stderr.contains($0) }) {
            throw PortBridgeError.serverUnreachable(host: server.host, reason: result.stderr)
        }

        // 3. 도구 부재 (NEW)
        if result.exitCode == 127 || stderr.contains("portbridge_tools_missing") {
            throw PortBridgeError.remoteToolsMissing
        }
    }

    // 기존 `if result.stdout.isEmpty { throw .remoteCommandNotFound }` 제거됨
```

전체 `scan()` 메서드 형태는 다음과 같이 정리된다:

```swift
func scan(server: Server, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
    let remoteCommand = """
    if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
      echo PORTBRIDGE_TOOLS_MISSING >&2
      exit 127
    fi
    ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
    """
    let args = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-p", "\(server.port)",
        server.sshTarget,
        remoteCommand
    ]

    let result = try await runner.run(sshExecutable, args: args, timeout: 15)

    if result.exitCode != 0 {
        let stderr = result.stderr.lowercased()

        if stderr.contains("permission denied") || stderr.contains("publickey") {
            throw PortBridgeError.sshAuthFailed(host: server.host)
        }

        let unreachablePatterns = [
            "connection timed out", "connect timeout",
            "no route to host",
            "connection refused",
            "could not resolve hostname", "name or service not known",
            "network is unreachable",
            "host is down",
        ]
        if unreachablePatterns.contains(where: { stderr.contains($0) }) {
            throw PortBridgeError.serverUnreachable(host: server.host, reason: result.stderr)
        }

        if result.exitCode == 127 || stderr.contains("portbridge_tools_missing") {
            throw PortBridgeError.remoteToolsMissing
        }
    }

    let first = result.stdout.components(separatedBy: .newlines).first ?? ""
    let parsed: [RemotePort]
    if first.uppercased().hasPrefix("LISTEN") || first.contains("State") {
        parsed = ScanOutputParser.parseSS(result.stdout)
    } else {
        parsed = ScanOutputParser.parseLsof(result.stdout)
    }

    let deduped = Self.deduplicateSamePort(parsed)
    return deduped
        .filter { range.contains($0.port) }
        .sorted { $0.port < $1.port }
}
```

- [ ] **Step 4: Run all scanner tests**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/PortScannerTests 2>&1 | tail -30
```

Expected: 모든 테스트 pass (`test_emptyStdoutWithoutErrorSignal_returnsEmptyArray` 포함).

- [ ] **Step 5: Commit**

```bash
git add PortBridge/Scanning/PortScanner.swift PortBridgeTests/PortScannerTests.swift
git commit -m "feat(scanner): classify tool absence via exit 127 + explicit marker

stdout.isEmpty 휴리스틱 제거. command -v 프로브가 둘 다 부재 시
PORTBRIDGE_TOOLS_MISSING + exit 127로 명시 신호. 빈 stdout이 정상
(listening 포트 없음) 케이스에서 더 이상 오류로 잡히지 않음.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: ViewModel — 새 오류를 새 상태로 매핑 + silent retry

**Files:**
- Modify: `PortBridge/ViewModels/ServerSectionViewModel.swift`
- Test: `PortBridgeTests/ServerSectionViewModelTests.swift`

`.serverUnreachable` → `.offline(isRetrying: false)`, `.remoteToolsMissing` → `.toolMissing`, 그리고 이전 상태가 `.offline`이면 `.scanning` 대신 `.offline(isRetrying: true)`로 전이.

- [ ] **Step 1: Update existing test name + write new tests**

`PortBridgeTests/ServerSectionViewModelTests.swift`의 기존 `test_scan_connectTimeout_setsError`를 다음으로 **교체**:

```swift
@MainActor
func test_scan_connectTimeout_setsOffline() async {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "Connection timed out")
    ]
    let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
    await vm.scan()
    guard case .offline(let isRetrying) = vm.scanState else {
        XCTFail("expected .offline, got \(vm.scanState)"); return
    }
    XCTAssertFalse(isRetrying)
}
```

같은 파일 끝에 추가:

```swift
@MainActor
func test_scan_noRouteToHost_setsOffline() async {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host prod port 22: No route to host")
    ]
    let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
    await vm.scan()
    if case .offline = vm.scanState { return }
    XCTFail("expected .offline, got \(vm.scanState)")
}

@MainActor
func test_scan_toolsMissing_setsToolMissing() async {
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 127, stdout: "", stderr: "PORTBRIDGE_TOOLS_MISSING")
    ]
    let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
    await vm.scan()
    XCTAssertEqual(vm.scanState, .toolMissing)
}

@MainActor
func test_scan_fromOffline_silentlyRetries() async {
    // 첫 스캔: 오프라인
    let mock = MockCommandRunner()
    mock.responses = [
        CommandResult(exitCode: 255, stdout: "", stderr: "No route to host"),
        CommandResult(exitCode: 255, stdout: "", stderr: "No route to host"),
    ]
    let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
    await vm.scan()
    guard case .offline(false) = vm.scanState else {
        XCTFail("expected .offline(false), got \(vm.scanState)"); return
    }

    // 재스캔: 시작 직후 isRetrying이 true여야 하지만, await 완료 후엔 다시 .offline(false)
    // 핵심 검증: .scanning을 거치지 않아야 함 — 직접 검증은 race-prone이므로
    // 최종 상태가 .offline 임을 검증하는 것으로 대체.
    await vm.scan()
    if case .offline = vm.scanState { return }
    XCTFail("expected .offline after retry, got \(vm.scanState)")
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/ServerSectionViewModelTests 2>&1 | tail -30
```

Expected: 4 tests fail (기존 connectTimeout 갱신 1개 + 신규 3개).

- [ ] **Step 3: Update ViewModel `scan()`**

`PortBridge/ViewModels/ServerSectionViewModel.swift`의 `scan()` 메서드 교체:

```swift
func scan() async {
    if case .scanning = scanState { return }
    if case .offline(true) = scanState { return }   // 이미 silent retry 중

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

- [ ] **Step 4: Run all ViewModel tests**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/ServerSectionViewModelTests 2>&1 | tail -30
```

Expected: 모든 테스트 pass.

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 모든 테스트 pass — 다른 테스트가 깨지지 않는지 확인.

- [ ] **Step 6: Commit**

```bash
git add PortBridge/ViewModels/ServerSectionViewModel.swift PortBridgeTests/ServerSectionViewModelTests.swift
git commit -m "feat(viewmodel): map new errors to new states + silent retry

serverUnreachable → .offline(false), remoteToolsMissing → .toolMissing.
이전 상태가 .offline이면 .scanning을 건너뛰고 .offline(isRetrying: true)로
직접 전이 — 헤더 ProgressView 노출 없이 상태 점 펄스만으로 진행 표현.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: ServerMonogram — 상태 점 지원

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift` (내부 `ServerMonogram`)

모노그램에 우하단 8px 상태 점 추가. 호출처는 Task 9–11에서 갱신.

- [ ] **Step 1: Add ServerStatusDot enum**

`PortBridge/Views/ServerSectionView.swift`의 `ServerMonogram` private struct **바로 위**에 추가:

```swift
enum ServerStatusDot: Equatable {
    case none
    case offline(pulse: Bool)
    case warning   // 노랑 — toolMissing / authFailed
    case online    // 녹색

    var fill: Color? {
        switch self {
        case .none: return nil
        case .offline: return .secondary.opacity(0.5)
        case .warning: return .orange
        case .online: return .green
        }
    }

    var pulses: Bool {
        if case .offline(true) = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Update ServerMonogram to accept status + dimmed**

기존 `private struct ServerMonogram: View` 전체 교체:

```swift
private struct ServerMonogram: View {
    let server: Server
    var status: ServerStatusDot = .none
    var dimmed: Bool = false

    private var initial: String {
        let source = server.name ?? server.host
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }

    private var hue: Double {
        var hash: UInt32 = 0x811c9dc5
        for byte in server.host.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x01000193
        }
        return Double(hash % 360) / 360.0
    }

    var body: some View {
        let tint = Color(
            hue: hue,
            saturation: Color.PB.Monogram.saturation,
            brightness: Color.PB.Monogram.brightness
        )
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(Color.PB.Monogram.fillOpacity))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(Color.PB.Monogram.strokeOpacity), lineWidth: 0.5)
                Text(initial)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)
            .opacity(dimmed ? 0.55 : 1.0)

            if let fill = status.fill {
                StatusDot(fill: fill, pulses: status.pulses)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct StatusDot: View {
    let fill: Color
    let pulses: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
            )
            .opacity(pulses ? (pulse ? 1.0 : 0.4) : 1.0)
            .scaleEffect(pulses ? (pulse ? 1.0 : 0.9) : 1.0)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: 빌드 성공 (기존 호출 `ServerMonogram(server: section.server)`는 기본값으로 동작).

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "feat(monogram): add ServerStatusDot with pulse animation

회색·노랑·녹색 점을 모노그램 우하단에 8px로 표시. 회색은 pulse 옵션
가능 (오프라인 재시도 중). 호출처 갱신은 후속 태스크.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: ToolInstallGuideView + InstallCommandRow 컴포넌트 작성

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift`

새 컴포넌트 두 개. `AuthFailedView` 패턴을 따라 노란 라벨 + 명령어 + 복사 버튼(아이콘 + 체크 전환).

- [ ] **Step 1: Add components at end of ServerSectionView.swift**

`PortBridge/Views/ServerSectionView.swift` 파일 끝(`AuthFailedView` 아래)에 추가:

```swift
private struct ToolInstallGuideView: View {
    private let commands: [(distro: String, command: String)] = [
        ("Debian / Ubuntu", "sudo apt install iproute2 lsof"),
        ("RHEL / CentOS",   "sudo yum install iproute lsof"),
        ("Alpine",          "apk add iproute2 lsof"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("원격 서버에 ss 또는 lsof가 필요합니다", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("포트 목록을 조회하려면 둘 중 하나가 설치되어 있어야 합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(commands, id: \.distro) { item in
                    InstallCommandRow(distro: item.distro, command: item.command)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct InstallCommandRow: View {
    let distro: String
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(distro)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

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
            .accessibilityLabel(copied ? "복사됨" : "\(distro) 명령 복사")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { copied = false }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: 빌드 성공 (아직 호출처 없음 — Task 8).

- [ ] **Step 3: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "feat(view): add ToolInstallGuideView with icon-based copy button

3종 배포판(Debian/RHEL/Alpine) 설치 명령을 노란 티어 인스트럭션으로
표시. 복사 버튼은 doc.on.doc → checkmark + symbolEffect 전환, 1.8s 자동
복귀. 호출처는 다음 태스크.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: AuthFailedView — 아이콘 복사 버튼으로 마이그레이션

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift` (내부 `AuthFailedView`)

기존 `"복사" / "복사됨 ✓"` 텍스트 버튼을 `InstallCommandRow`와 동일한 아이콘 패턴으로 변경. 시각 일관성 확보.

- [ ] **Step 1: Replace AuthFailedView body**

`PortBridge/Views/ServerSectionView.swift`의 `private struct AuthFailedView: View` 전체 교체:

```swift
private struct AuthFailedView: View {
    let copyCommand: String
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SSH 키 인증 실패", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack(spacing: 8) {
                Text(verbatim: copyCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyCommand, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { copied = false }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: 빌드 성공.

- [ ] **Step 3: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "refactor(view): migrate AuthFailedView copy button to icon pattern

기존 텍스트 '복사' / '복사됨 ✓' → doc.on.doc / checkmark 아이콘.
InstallCommandRow와 시각 어휘 통일 — 두 노란 티어가 같은 복사 UX 공유.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: ServerSectionView — .offline 상태 렌더링

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift`

`.offline` 상태에서 chevron · ↻ 숨김, 모노그램 dimmed, 회색 점(필요시 펄스), body 미렌더, row 탭 = `scan()`.

- [ ] **Step 1: Update sectionHeader and sectionContent**

`PortBridge/Views/ServerSectionView.swift`의 `ServerSectionView` 본체에 헬퍼 + 분기 추가.

먼저 `body`를 다음으로 교체:

```swift
var body: some View {
    sectionHeader
    if section.isExpanded && !isOffline {
        sectionContent
    }
}

private var isOffline: Bool {
    if case .offline = section.scanState { return true }
    return false
}

private var statusDot: ServerStatusDot {
    switch section.scanState {
    case .offline(let isRetrying): return .offline(pulse: isRetrying)
    case .toolMissing, .authFailed: return .warning
    case .loaded: return .online
    default: return .none
    }
}
```

다음, `sectionHeader`의 chevron Button과 refresh Button을 조건부로 렌더. **전체 `sectionHeader` 교체**:

```swift
private var sectionHeader: some View {
    HStack(spacing: 8) {
        if !isOffline {
            Button(action: toggleExpandedAnimated) {
                Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .transaction { $0.animation = nil }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.isExpanded ? "접기" : "펼치기")
        } else {
            // 12px 자리 비움 — 다른 행과 가로 정렬 유지
            Color.clear.frame(width: 12, height: 12)
        }

        ServerMonogram(server: section.server, status: statusDot, dimmed: isOffline)
            .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 1) {
            Text(primaryLabel)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(isOffline ? .secondary : .primary)
                .lineLimit(1)
            Text(secondaryLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        Spacer(minLength: 8)

        if activeCount > 0 && !isOffline {
            Text("\(activeCount)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.PB.accentBadgeBg, in: Capsule())
                .help("이 서버에서 포워딩 중인 포트 수")
                .accessibilityLabel("포워딩 중인 포트 \(activeCount)개")
        }

        if case .scanning = section.scanState {
            ProgressView().controlSize(.small)
        } else if !isOffline {
            Button { Task { await section.scan() } } label: {
                Image(systemName: "arrow.clockwise").font(.body).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("\(primaryLabel) 포트 재스캔")
            .accessibilityLabel("\(primaryLabel) 포트 재스캔")
        }

        Menu {
            Button("편집…", action: onEdit)
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis").font(.body).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .accessibilityLabel("\(primaryLabel) 더보기")
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { handleRowTap() }
}

private func handleRowTap() {
    if isOffline {
        Task { await section.scan() }
    } else {
        toggleExpandedAnimated()
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: 빌드 성공.

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 모든 테스트 pass.

- [ ] **Step 4: Manual smoke test — offline rendering**

앱을 실행하고, 도달 불가능한 IP로 서버 추가 (예: `192.0.2.1` — TEST-NET-1, 보장된 미할당) 후 ↻ 또는 row 탭. 다음을 확인:

- chevron이 보이지 않음 (12px 빈 공간 유지)
- ↻ 버튼이 보이지 않음 (⋯ 메뉴만 남음)
- 모노그램이 dimmed (opacity 0.55 정도)
- primary 텍스트가 secondary 톤
- 모노그램 우하단에 회색 점
- 재시도 중일 때 회색 점이 펄스
- row 탭 시 본문 펼침 없이 silent scan 발화 (헤더에 ProgressView 없음)

- [ ] **Step 5: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "feat(view): render .offline state with silent retry affordance

오프라인 시 chevron · ↻ 숨김, 모노그램 dimmed, 회색 상태 점(필요시
펄스), body 미렌더. row 탭이 scan()을 직접 호출. handleRowTap 헬퍼로
오프라인/일반 분기 일원화. chevron에 .transaction(animation: nil)로
펼침 spring과 분리.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: ServerSectionView — .toolMissing 상태 렌더링

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift`

`.toolMissing`일 때 body에 `ToolInstallGuideView` 표시. 헤더는 정상(노란 점은 Task 6의 statusDot 헬퍼가 이미 처리).

- [ ] **Step 1: Update sectionContent switch**

`PortBridge/Views/ServerSectionView.swift`의 `sectionContent`에서 Task 2에서 추가한 stub 교체:

```swift
case .offline:
    EmptyView()   // 안전망 — body는 isOffline 분기로 이미 미렌더되지만 switch exhaustiveness 위해 유지

case .toolMissing:
    ToolInstallGuideView()
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: 빌드 성공.

- [ ] **Step 3: Manual smoke test — toolMissing rendering**

`ss`/`lsof` 둘 다 없는 환경을 재현하기 어려울 수 있으니, 임시로 `PortScanner.scan()`의 `remoteCommand`를 `exit 127` 직접 반환하도록 바꿔 테스트 (테스트 후 되돌리기):

```swift
let remoteCommand = "echo PORTBRIDGE_TOOLS_MISSING >&2; exit 127"
```

스캔 후 다음 확인:
- 모노그램 우하단에 노란 점
- 본문에 "원격 서버에 ss 또는 lsof가 필요합니다" 라벨 (오렌지 색)
- 3개 배포판 명령 표시
- 각 명령 오른쪽에 doc.on.doc 아이콘 버튼
- 클릭 시 아이콘이 checkmark(녹색)으로 전환되고 1.8초 후 복귀
- 클립보드에 명령이 실제로 복사되었는지 확인 (다른 앱에 붙여넣기)

테스트 후 `remoteCommand`를 원래대로 복원.

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "feat(view): render .toolMissing with install guide

ToolInstallGuideView로 3종 배포판 명령 노출. 노란 상태 점은
statusDot 헬퍼가 이미 처리.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: 사용되지 않는 PortBridgeError 케이스 제거

**Files:**
- Modify: `PortBridge/Models/PortBridgeError.swift`
- Modify: `PortBridgeTests/PortBridgeErrorTests.swift`

`sshConnectTimeout` · `remoteCommandNotFound`은 더 이상 throw되지 않음. 코드 전체에서 참조도 없음을 확인 후 제거.

- [ ] **Step 1: Verify no references remain**

```bash
grep -rn "sshConnectTimeout\|remoteCommandNotFound" --include="*.swift" /Users/youngho.jeon/datamaker/PortBridge/
```

Expected: `PortBridge/Models/PortBridgeError.swift`의 enum 정의와 `errorDescription` switch만 출력. 다른 파일에서 0개 hit.

만약 다른 파일에서 hit이 있다면 그 호출처를 먼저 수정한 뒤 진행.

- [ ] **Step 2: Remove cases from enum and errorDescription**

`PortBridge/Models/PortBridgeError.swift` 전체 (참고: `scanOutputUnparseable` · `localPortInUse` · `tunnelCrashed`는 이미 커밋 `5be8a89`에서 dead code로 제거된 상태):

```swift
import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case serverUnreachable(host: String, reason: String)
    case remoteToolsMissing
    case forwardingDiedEarly(stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .serverUnreachable(let host, _):
            return "\(host) 서버에 연결할 수 없습니다."
        case .remoteToolsMissing:
            return "원격 서버에 ss 또는 lsof가 필요합니다."
        case .forwardingDiedEarly(let stderr):
            return "포워딩이 즉시 종료되었습니다: \(stderr)"
        }
    }
}
```

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 모든 테스트 pass.

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Models/PortBridgeError.swift
git commit -m "refactor(error): remove deprecated sshConnectTimeout / remoteCommandNotFound

두 케이스 모두 throw 지점 없음을 확인 후 제거. 오프라인 / 도구 부재는
각각 .serverUnreachable / .remoteToolsMissing이 대체.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: 통합 검증 — 시안 매칭 + 전체 회귀

**Files:** (수정 없음 — 검증만)

빌드 + 전체 테스트 + 수동 시나리오 5개 확인.

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 모든 테스트 pass.

- [ ] **Step 2: Build release config**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -configuration Release -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: 경고 없는 빌드 성공.

- [ ] **Step 3: Manual scenarios**

앱 실행 후 다음 5개 시나리오 검증. 시안([/tmp/portbridge-offline-mockup.html](/tmp/portbridge-offline-mockup.html))과 비교.

1. **온라인 서버**: 정상 SSH 가능한 서버 → 녹색 상태 점, 포트 목록 표시.
2. **오프라인 서버**: 도달 불가능한 IP (`192.0.2.1`) → 회색 점, chevron/↻ 숨김, 모노그램 dimmed, body 미표시. row 탭 → 점 펄스, 헤더에 ProgressView 없음.
3. **인증 실패**: 잘못된 키 등록된 서버 → 노란 점, `AuthFailedView` 표시, 복사 버튼이 아이콘.
4. **도구 부재**: (Task 10에서 시도한 방식으로 임시 재현) → 노란 점, `ToolInstallGuideView` 표시, 3개 배포판 복사 버튼 동작.
5. **chevron 무애니메이션**: 일반 섹션 펼치기/접기 → chevron이 즉시 교체(회전 애니메이션 없음), body는 spring으로 펼침.

- [ ] **Step 4: Update mockup reference (optional)**

`/tmp/portbridge-offline-mockup.html`은 휘발성 위치. 영구 보존이 필요하면 `docs/superpowers/specs/2026-05-21-server-status-tier-design.md`의 §12 시안 링크를 `docs/superpowers/assets/`로 옮긴 후 갱신. 옵션이므로 skip 가능.

- [ ] **Step 5: Final commit (옵션 — 추가 변경 없으면 생략)**

코드 변경 없는 검증 단계라 별도 커밋 없이 종료. 모든 시나리오가 통과하면 PR 작성 단계로 진행.

---

## Files Changed Summary

| 파일 | 작업 |
|---|---|
| `PortBridge/Models/PortBridgeError.swift` | `.serverUnreachable` / `.remoteToolsMissing` 추가, `.sshConnectTimeout` / `.remoteCommandNotFound` 제거 |
| `PortBridge/ViewModels/ServerSectionViewModel.swift` | `ServerScanState`에 `.offline` / `.toolMissing` 추가, `scan()` 분기 보강 |
| `PortBridge/Scanning/PortScanner.swift` | 도구 프로브 + 6종 unreachable 패턴 분류 + 도구 부재 분류, `stdout.isEmpty` 휴리스틱 제거 |
| `PortBridge/Views/ServerSectionView.swift` | `ServerStatusDot` enum, `ServerMonogram` 보강, `StatusDot`/`ToolInstallGuideView`/`InstallCommandRow` 추가, `AuthFailedView` 아이콘 복사로 마이그레이션, `sectionHeader`/`body` 상태별 분기, chevron `.transaction(nil)` |
| `PortBridgeTests/PortBridgeErrorTests.swift` | 새 케이스 검증 추가 |
| `PortBridgeTests/PortScannerTests.swift` | 6종 unreachable + 도구 부재 + 빈 stdout 정상 케이스 추가 |
| `PortBridgeTests/ServerSectionViewModelTests.swift` | `connectTimeout_setsError` → `connectTimeout_setsOffline`로 갱신, `noRouteToHost` / `toolsMissing` / `silentlyRetries` 추가 |
