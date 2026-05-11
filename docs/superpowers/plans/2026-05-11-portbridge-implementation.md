# PortBridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 14+ SwiftUI 앱 PortBridge를 구현 — `~/.ssh/config` 호스트에서 리모트 TCP 리스닝 포트를 스캔하고 `ssh -L` 포워딩을 토글로 관리.

**Architecture:** 단일 Xcode 앱 타겟. 폴더로 관심사 분리(`SSH/`, `Scanning/`, `Tunneling/`, `Models/`, `ViewModels/`, `Views/`). `CommandRunner` protocol로 외부 프로세스 호출을 추상화해 파서·스캐너는 순수함수 TDD. UI는 `@MainActor @Observable AppViewModel` 하나가 상태 허브.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation `Process`, XCTest. 외부 라이브러리 없음. App Sandbox OFF.

**Spec reference:** `docs/superpowers/specs/2026-05-11-portbridge-design.md`

---

## Phase 1: 프로젝트 부트스트랩

### Task 1: Xcode 프로젝트 생성 (수동)

이 단계는 Xcode를 통해 사용자가 수행한다. SwiftUI macOS 앱의 표준 `.xcodeproj` 구조를 만드는 가장 안정적인 방법이다.

**Files:** `PortBridge.xcodeproj/` (생성됨), `PortBridge/PortBridgeApp.swift`, `PortBridge/ContentView.swift`, `PortBridgeTests/`

- [ ] **Step 1: Xcode에서 새 프로젝트 생성**

Xcode 메뉴 → File → New → Project → macOS → App. 아래 옵션으로 작성:
- Product Name: `PortBridge`
- Team: 본인 Apple ID (또는 None)
- Organization Identifier: `io.datamaker` (또는 본인 도메인)
- Interface: **SwiftUI**
- Language: **Swift**
- Include Tests: **체크**
- Storage: None
- Save 위치: `~/datamaker/PortBridge` (기존 디렉토리 선택, "Create Git repository"는 **체크 해제** — 이미 git 초기화됨)

- [ ] **Step 2: 빌드 설정 조정**

Xcode 프로젝트 네비게이터에서 PortBridge 타겟 선택 → General 탭:
- Minimum Deployments: **macOS 14.0**
- App Sandbox는 Signing & Capabilities 탭에서 **삭제** (기본 Capability에 있으면 'x' 클릭)

- [ ] **Step 3: 빌드 한 번 실행해 통과 확인**

`Cmd+B` 또는:
```bash
cd ~/datamaker/PortBridge
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
cd ~/datamaker/PortBridge
git add -A
git commit -m "chore: bootstrap Xcode SwiftUI app (macOS 14, sandbox off)"
```

---

### Task 2: 폴더 그룹 구성

**Files:** 신규 그룹/디렉토리만 생성. 파일은 다음 태스크부터 채운다.

- [ ] **Step 1: 디렉토리 생성**

```bash
cd ~/datamaker/PortBridge/PortBridge
mkdir -p Models SSH Scanning Tunneling ViewModels Views
cd ../PortBridgeTests
mkdir -p Fixtures/config.d
```

- [ ] **Step 2: Xcode에서 그룹 동기화**

Xcode에서 PortBridge 폴더를 우클릭 → "Add Files to PortBridge" → 위에서 만든 6개 폴더를 모두 선택 → "Create groups" 선택, "Copy items if needed" 체크 해제. PortBridgeTests 폴더도 같은 방법으로 `Fixtures`를 추가.

(빈 폴더는 git이 추적하지 않으므로 .gitkeep을 잠깐 둔다)

```bash
cd ~/datamaker/PortBridge
touch PortBridge/Models/.gitkeep PortBridge/SSH/.gitkeep PortBridge/Scanning/.gitkeep PortBridge/Tunneling/.gitkeep PortBridge/ViewModels/.gitkeep PortBridge/Views/.gitkeep PortBridgeTests/Fixtures/.gitkeep
```

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "chore: scaffold module folders (Models, SSH, Scanning, Tunneling, ViewModels, Views)"
```

---

## Phase 2: 도메인 모델

### Task 3: `SSHHost` 모델

**Files:**
- Create: `PortBridge/Models/SSHHost.swift`
- Test: `PortBridgeTests/SSHHostTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`PortBridgeTests/SSHHostTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class SSHHostTests: XCTestCase {
    func test_id_equalsName() {
        let host = SSHHost(name: "prod", hostName: "10.0.0.1", user: "ubuntu", port: 22)
        XCTAssertEqual(host.id, "prod")
    }

    func test_minimalHost_hasOptionalFieldsAsNil() {
        let host = SSHHost(name: "bare")
        XCTAssertEqual(host.name, "bare")
        XCTAssertNil(host.hostName)
        XCTAssertNil(host.user)
        XCTAssertNil(host.port)
    }
}
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: 컴파일 에러 ("cannot find SSHHost in scope").

- [ ] **Step 3: 모델 구현**

`PortBridge/Models/SSHHost.swift`:

```swift
import Foundation

struct SSHHost: Identifiable, Hashable {
    let name: String
    var hostName: String? = nil
    var user: String? = nil
    var port: Int? = nil

    var id: String { name }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `Test Suite 'SSHHostTests' passed`.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat(models): add SSHHost"
```

---

### Task 4: `RemotePort` 모델

**Files:**
- Create: `PortBridge/Models/RemotePort.swift`
- Test: `PortBridgeTests/RemotePortTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`PortBridgeTests/RemotePortTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class RemotePortTests: XCTestCase {
    func test_id_combinesAddressAndPort() {
        let p = RemotePort(port: 5432, address: "0.0.0.0", processName: "postgres")
        XCTAssertEqual(p.id, "0.0.0.0:5432")
    }

    func test_processNameOptional() {
        let p = RemotePort(port: 8080, address: "127.0.0.1", processName: nil)
        XCTAssertNil(p.processName)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run tests → "cannot find RemotePort".

- [ ] **Step 3: 모델 구현**

`PortBridge/Models/RemotePort.swift`:

```swift
import Foundation

struct RemotePort: Identifiable, Hashable {
    let port: Int
    let address: String
    let processName: String?

    var id: String { "\(address):\(port)" }
}
```

- [ ] **Step 4: 통과 확인 → 커밋**

```bash
git add -A
git commit -m "feat(models): add RemotePort"
```

---

### Task 5: `Forwarding` 모델 + 상태 enum

**Files:**
- Create: `PortBridge/Models/Forwarding.swift`
- Test: `PortBridgeTests/ForwardingTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    func test_idUnique() {
        let a = Forwarding(host: "h", remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(host: "h", remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }
}
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: 모델 구현**

`PortBridge/Models/Forwarding.swift`:

```swift
import Foundation

struct Forwarding: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case starting
        case active
        case error(String)
    }

    let id: UUID
    let host: String
    let remotePort: Int
    var localPort: Int
    var state: State

    init(id: UUID = UUID(), host: String, remotePort: Int, localPort: Int, state: State) {
        self.id = id
        self.host = host
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
    }
}
```

- [ ] **Step 4: 통과 → 커밋**

```bash
git add -A
git commit -m "feat(models): add Forwarding with state enum"
```

---

### Task 6: `PortBridgeError` enum

**Files:**
- Create: `PortBridge/Models/PortBridgeError.swift`
- Test: `PortBridgeTests/PortBridgeErrorTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import PortBridge

final class PortBridgeErrorTests: XCTestCase {
    func test_localPortInUse_hasDescription() {
        let err = PortBridgeError.localPortInUse(8080)
        XCTAssertTrue(err.errorDescription?.contains("8080") ?? false)
    }

    func test_sshAuthFailed_includesHost() {
        let err = PortBridgeError.sshAuthFailed(host: "prod")
        XCTAssertTrue(err.errorDescription?.contains("prod") ?? false)
    }
}
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: enum 구현**

`PortBridge/Models/PortBridgeError.swift`:

```swift
import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshConfigNotFound
    case sshConfigUnreadable(String)
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)
    case remoteCommandNotFound
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: UUID, stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshConfigNotFound:
            return "~/.ssh/config 파일을 찾을 수 없습니다."
        case .sshConfigUnreadable(let reason):
            return "ssh config을 읽지 못했습니다: \(reason)"
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .sshConnectTimeout(let host):
            return "\(host) 연결 타임아웃."
        case .remoteCommandNotFound:
            return "리모트에 ss/lsof 어느 쪽도 없습니다."
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

- [ ] **Step 4: 통과 → 커밋**

```bash
git add -A
git commit -m "feat(models): add PortBridgeError"
```

---

## Phase 3: SSH 설정 파서

### Task 7: `SSHConfigParser` — 기본 Host 라인

**Files:**
- Create: `PortBridge/SSH/SSHConfigParser.swift`
- Test: `PortBridgeTests/SSHConfigParserTests.swift`
- Test fixture: `PortBridgeTests/Fixtures/config_basic.txt`

- [ ] **Step 1: 픽스처 작성**

`PortBridgeTests/Fixtures/config_basic.txt`:

```
Host prod
    HostName 10.0.0.1
    User ubuntu
    Port 2222

Host staging
    HostName 10.0.0.2
    User deploy
```

- [ ] **Step 2: 실패 테스트 작성**

`PortBridgeTests/SSHConfigParserTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class SSHConfigParserTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle(for: type(of: self)).url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
    }

    func test_basic_parsesTwoHostsWithOptions() throws {
        let hosts = try SSHConfigParser.parse(path: fixtureURL("config_basic"))
        XCTAssertEqual(hosts.count, 2)

        let prod = hosts.first { $0.name == "prod" }
        XCTAssertEqual(prod?.hostName, "10.0.0.1")
        XCTAssertEqual(prod?.user, "ubuntu")
        XCTAssertEqual(prod?.port, 2222)

        let staging = hosts.first { $0.name == "staging" }
        XCTAssertEqual(staging?.hostName, "10.0.0.2")
        XCTAssertEqual(staging?.user, "deploy")
        XCTAssertNil(staging?.port)
    }
}
```

- [ ] **Step 3: Fixture 번들 포함**

Xcode 프로젝트에서 `PortBridgeTests/Fixtures` 폴더를 PortBridgeTests 타겟의 "Copy Bundle Resources" 빌드 단계에 포함되도록 확인. Xcode가 기본으로 폴더 추가 시 자동 포함하지만, 빌드 페이즈에서 확인.

- [ ] **Step 4: 실패 확인**

테스트 실행 → "cannot find SSHConfigParser".

- [ ] **Step 5: 파서 구현 (Host + 기본 옵션만)**

`PortBridge/SSH/SSHConfigParser.swift`:

```swift
import Foundation

enum SSHConfigParser {
    static func parse(
        path: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".ssh/config")
    ) throws -> [SSHHost] {
        var visited = Set<URL>()
        return try parseRecursive(path: path, visited: &visited)
    }

    private static func parseRecursive(path: URL, visited: inout Set<URL>) throws -> [SSHHost] {
        let resolved = path.standardizedFileURL
        guard !visited.contains(resolved) else { return [] }
        visited.insert(resolved)

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw PortBridgeError.sshConfigNotFound
        }

        let content: String
        do {
            content = try String(contentsOf: resolved, encoding: .utf8)
        } catch {
            throw PortBridgeError.sshConfigUnreadable(error.localizedDescription)
        }

        var results: [SSHHost] = []
        var current: [String]? = nil
        var currentOptions: [String: String] = [:]

        func flush() {
            guard let names = current else { return }
            for name in names where !name.contains("*") && !name.contains("?") && !name.contains("!") {
                results.append(SSHHost(
                    name: name,
                    hostName: currentOptions["hostname"],
                    user: currentOptions["user"],
                    port: currentOptions["port"].flatMap { Int($0) }
                ))
            }
            current = nil
            currentOptions = [:]
        }

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let keyword = parts[0].lowercased()
            let values = Array(parts[1...])

            switch keyword {
            case "host":
                flush()
                current = values
            case "hostname", "user", "port":
                currentOptions[keyword] = values.first
            default:
                break
            }
        }
        flush()

        return results
    }
}
```

- [ ] **Step 6: 통과 확인 → 커밋**

```bash
git add -A
git commit -m "feat(ssh): basic SSHConfigParser handles Host + HostName/User/Port"
```

---

### Task 8: `SSHConfigParser` — 와일드카드 제외 & 다중 호스트 라인

**Files:**
- Modify: `PortBridge/SSH/SSHConfigParser.swift` (이미 와일드카드 제외 로직 포함)
- Test: `PortBridgeTests/SSHConfigParserTests.swift`
- Test fixture: `PortBridgeTests/Fixtures/config_wildcard.txt`

- [ ] **Step 1: 픽스처 작성**

`PortBridgeTests/Fixtures/config_wildcard.txt`:

```
Host *
    ServerAliveInterval 60

Host prod
    HostName 10.0.0.1

Host db1 db2 db3
    User postgres

Host !blocked
    HostName ignored
```

- [ ] **Step 2: 실패 테스트 추가**

`SSHConfigParserTests.swift`에 추가:

```swift
func test_wildcardHosts_excluded() throws {
    let hosts = try SSHConfigParser.parse(path: fixtureURL("config_wildcard"))
    XCTAssertFalse(hosts.contains { $0.name == "*" })
    XCTAssertFalse(hosts.contains { $0.name == "!blocked" })
}

func test_multipleHostsOnOneLine_eachRegistered() throws {
    let hosts = try SSHConfigParser.parse(path: fixtureURL("config_wildcard"))
    let names = hosts.map(\.name)
    XCTAssertTrue(names.contains("db1"))
    XCTAssertTrue(names.contains("db2"))
    XCTAssertTrue(names.contains("db3"))
    let dbs = hosts.filter { $0.name.hasPrefix("db") }
    XCTAssertTrue(dbs.allSatisfy { $0.user == "postgres" })
}
```

- [ ] **Step 3: 테스트 실행 — Task 7의 구현이 이미 처리하므로 통과해야 함**

만약 실패한다면 구현 점검. 통과하면 다음.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "test(ssh): wildcard exclusion and multi-host line"
```

---

### Task 9: `SSHConfigParser` — Include 재귀

**Files:**
- Modify: `PortBridge/SSH/SSHConfigParser.swift`
- Test: `PortBridgeTests/SSHConfigParserTests.swift`
- Fixtures: `Fixtures/config_include.txt`, `Fixtures/config.d/extra.txt`

- [ ] **Step 1: 픽스처 작성**

`Fixtures/config_include.txt`:

```
Host main
    HostName 10.0.0.10

Include config.d/extra.txt
```

`Fixtures/config.d/extra.txt`:

```
Host included
    HostName 10.0.0.20
    User extra
```

- [ ] **Step 2: 실패 테스트 추가**

```swift
func test_include_recursivelyLoadsSubFile() throws {
    let hosts = try SSHConfigParser.parse(path: fixtureURL("config_include"))
    let names = hosts.map(\.name)
    XCTAssertTrue(names.contains("main"))
    XCTAssertTrue(names.contains("included"))
    let included = hosts.first { $0.name == "included" }
    XCTAssertEqual(included?.user, "extra")
}
```

- [ ] **Step 3: 실패 확인**

테스트 실행 → "included" 가 결과에 없음.

- [ ] **Step 4: Include 처리 추가**

`SSHConfigParser.swift`의 `switch keyword` 블록에 case 추가:

```swift
case "include":
    flush()
    for value in values {
        let expanded = expandIncludePath(value, relativeTo: resolved)
        for matched in expanded {
            let sub = try parseRecursive(path: matched, visited: &visited)
            results.append(contentsOf: sub)
        }
    }
```

같은 파일에 헬퍼 추가:

```swift
private static func expandIncludePath(_ pattern: String, relativeTo configFile: URL) -> [URL] {
    let expanded = (pattern as NSString).expandingTildeInPath
    let base: URL
    if expanded.hasPrefix("/") {
        base = URL(fileURLWithPath: expanded)
    } else {
        base = configFile.deletingLastPathComponent().appending(path: expanded)
    }

    // 글롭 미포함이면 단일 파일
    if !expanded.contains("*") && !expanded.contains("?") {
        return [base]
    }

    let dir = base.deletingLastPathComponent()
    let glob = base.lastPathComponent
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
        return []
    }
    return entries
        .filter { fnmatch(glob, $0) }
        .map { dir.appending(path: $0) }
}

private static func fnmatch(_ pattern: String, _ name: String) -> Bool {
    // 간단한 글롭: * 와 ? 만 지원
    let p = pattern.map { Character.init($0) }
    let n = name.map { Character.init($0) }
    return globMatch(p, 0, n, 0)
}

private static func globMatch(_ p: [Character], _ pi: Int, _ s: [Character], _ si: Int) -> Bool {
    if pi == p.count { return si == s.count }
    if p[pi] == "*" {
        if pi + 1 == p.count { return true }
        var k = si
        while k <= s.count {
            if globMatch(p, pi + 1, s, k) { return true }
            k += 1
        }
        return false
    }
    if si == s.count { return false }
    if p[pi] == "?" || p[pi] == s[si] {
        return globMatch(p, pi + 1, s, si + 1)
    }
    return false
}
```

- [ ] **Step 5: 통과 확인 → 커밋**

```bash
git add -A
git commit -m "feat(ssh): Include directive recursive expansion"
```

---

## Phase 4: 외부 프로세스 실행 추상화

### Task 10: `CommandRunner` protocol

**Files:**
- Create: `PortBridge/SSH/CommandRunner.swift`

- [ ] **Step 1: 인터페이스 정의 (테스트는 다음 태스크에서)**

`PortBridge/SSH/CommandRunner.swift`:

```swift
import Foundation

struct CommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner: Sendable {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult
}

enum CommandError: Error, Equatable {
    case timedOut
    case launchFailed(String)
}
```

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "feat(ssh): CommandRunner protocol + CommandResult"
```

---

### Task 11: `MockCommandRunner` (테스트 헬퍼) + `ProcessCommandRunner`

**Files:**
- Create: `PortBridge/SSH/ProcessCommandRunner.swift`
- Create: `PortBridgeTests/MockCommandRunner.swift`
- Test: `PortBridgeTests/ProcessCommandRunnerTests.swift`

- [ ] **Step 1: Mock 작성 (테스트 타겟)**

`PortBridgeTests/MockCommandRunner.swift`:

```swift
import Foundation
@testable import PortBridge

final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    var calls: [Call] = []
    var responses: [CommandResult] = []
    var error: Error?

    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable, args: args))
        if let error = error { throw error }
        guard !responses.isEmpty else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return responses.removeFirst()
    }
}
```

- [ ] **Step 2: 실제 ProcessCommandRunner 구현**

`PortBridge/SSH/ProcessCommandRunner.swift`:

```swift
import Foundation

final class ProcessCommandRunner: CommandRunner, @unchecked Sendable {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withThrowingTaskGroup(of: CommandResult?.self) { group in
            group.addTask {
                try process.run()

                async let stdoutData = Self.readAll(stdoutPipe.fileHandleForReading)
                async let stderrData = Self.readAll(stderrPipe.fileHandleForReading)

                process.waitUntilExit()
                let so = await stdoutData
                let se = await stderrData
                return CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: so, encoding: .utf8) ?? "",
                    stderr: String(data: se, encoding: .utf8) ?? ""
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
                return nil
            }

            defer { group.cancelAll() }
            for try await result in group {
                if let result = result { return result }
                throw CommandError.timedOut
            }
            throw CommandError.launchFailed("no result")
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached {
            (try? handle.readToEnd()) ?? Data()
        }.value
    }
}
```

- [ ] **Step 3: 가벼운 smoke 테스트**

`PortBridgeTests/ProcessCommandRunnerTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class ProcessCommandRunnerTests: XCTestCase {
    func test_echo_returnsStdout() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run("/bin/echo", args: ["hello"], timeout: 2)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .newlines), "hello")
    }

    func test_falseExitsWithOne() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run("/usr/bin/false", args: [], timeout: 2)
        XCTAssertEqual(result.exitCode, 1)
    }
}
```

- [ ] **Step 4: 테스트 통과 → 커밋**

```bash
git add -A
git commit -m "feat(ssh): ProcessCommandRunner + MockCommandRunner test helper"
```

---

## Phase 5: 포트 스캐닝

### Task 12: `ScanOutputParser.parseSS`

**Files:**
- Create: `PortBridge/Scanning/ScanOutputParser.swift`
- Test: `PortBridgeTests/ScanOutputParserTests.swift`
- Fixtures: `ss_ipv4_only.txt`, `ss_ipv6_mixed.txt`, `ss_no_header.txt`

- [ ] **Step 1: 픽스처 작성**

`Fixtures/ss_no_header.txt` (ss -tlnH 출력 시뮬레이션 — 헤더 없음):

```
LISTEN 0 128 0.0.0.0:22 0.0.0.0:*
LISTEN 0 100 127.0.0.1:5432 0.0.0.0:*
LISTEN 0 128 [::]:80 [::]:*
LISTEN 0 50  127.0.0.1:8080 0.0.0.0:*
```

`Fixtures/ss_ipv4_only.txt`:

```
State Recv-Q Send-Q Local Address:Port Peer Address:Port
LISTEN 0 128 0.0.0.0:22 0.0.0.0:*
LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*
```

`Fixtures/ss_ipv6_mixed.txt`:

```
State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=1,fd=3))
LISTEN 0 100 [::1]:5432 [::]:*
LISTEN 0 128 0.0.0.0:443 0.0.0.0:*
```

- [ ] **Step 2: 실패 테스트 작성**

`PortBridgeTests/ScanOutputParserTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class ScanOutputParserTests: XCTestCase {
    private func fixture(_ name: String) -> String {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func test_parseSS_noHeader_threePorts() {
        let ports = ScanOutputParser.parseSS(fixture("ss_no_header"))
        XCTAssertEqual(ports.count, 4)
        XCTAssertTrue(ports.contains { $0.port == 22 && $0.address == "0.0.0.0" })
        XCTAssertTrue(ports.contains { $0.port == 5432 && $0.address == "127.0.0.1" })
        XCTAssertTrue(ports.contains { $0.port == 80 && $0.address == "::" })
    }

    func test_parseSS_withHeader_skipsHeaderLine() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv4_only"))
        XCTAssertEqual(ports.count, 2)
    }

    func test_parseSS_ipv6Mixed_handlesBrackets() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv6_mixed"))
        XCTAssertEqual(ports.count, 3)
        XCTAssertTrue(ports.contains { $0.port == 22 && $0.address == "::" })
        XCTAssertTrue(ports.contains { $0.port == 5432 && $0.address == "::1" })
    }

    func test_parseSS_extractsProcessName() {
        let ports = ScanOutputParser.parseSS(fixture("ss_ipv6_mixed"))
        let p22 = ports.first { $0.port == 22 }
        XCTAssertEqual(p22?.processName, "sshd")
    }
}
```

- [ ] **Step 3: 실패 확인**

- [ ] **Step 4: 구현**

`PortBridge/Scanning/ScanOutputParser.swift`:

```swift
import Foundation

enum ScanOutputParser {
    static func parseSS(_ output: String) -> [RemotePort] {
        var results: [RemotePort] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // 헤더 스킵: 첫 단어가 LISTEN/ESTAB 등 상태가 아니면 패스
            let firstWord = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            if firstWord.uppercased() != "LISTEN" { continue }

            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 4 else { continue }
            let localAddr = cols[3]

            guard let (addr, port) = splitAddressPort(localAddr) else { continue }
            let procName = extractProcessName(line)
            results.append(RemotePort(port: port, address: addr, processName: procName))
        }
        return results
    }

    private static func splitAddressPort(_ s: String) -> (String, Int)? {
        // [::]:80, [::1]:5432, 0.0.0.0:22
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let addr = String(s[s.index(after: s.startIndex)..<close])
            let afterClose = s.index(after: close)
            guard afterClose < s.endIndex, s[afterClose] == ":" else { return nil }
            let portStr = String(s[s.index(after: afterClose)...])
            guard let port = Int(portStr) else { return nil }
            return (addr, port)
        } else {
            guard let colon = s.lastIndex(of: ":") else { return nil }
            let addr = String(s[..<colon])
            let portStr = String(s[s.index(after: colon)...])
            guard let port = Int(portStr) else { return nil }
            return (addr, port)
        }
    }

    private static func extractProcessName(_ line: String) -> String? {
        // users:(("sshd",pid=...))
        guard let usersRange = line.range(of: "users:((") else { return nil }
        let rest = line[usersRange.upperBound...]
        guard let quoteStart = rest.firstIndex(of: "\"") else { return nil }
        let afterQuote = rest.index(after: quoteStart)
        guard let quoteEnd = rest[afterQuote...].firstIndex(of: "\"") else { return nil }
        return String(rest[afterQuote..<quoteEnd])
    }
}
```

- [ ] **Step 5: 통과 → 커밋**

```bash
git add -A
git commit -m "feat(scanning): parseSS handles IPv4/IPv6/process name"
```

---

### Task 13: `ScanOutputParser.parseLsof`

**Files:**
- Modify: `PortBridge/Scanning/ScanOutputParser.swift`
- Test: `PortBridgeTests/ScanOutputParserTests.swift`
- Fixtures: `lsof_typical.txt`, `lsof_no_process.txt`

- [ ] **Step 1: 픽스처 작성**

`Fixtures/lsof_typical.txt`:

```
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
sshd     1   root   3u   IPv4  12345      0t0  TCP *:22 (LISTEN)
postgres 100 postgres 5u IPv4  23456      0t0  TCP 127.0.0.1:5432 (LISTEN)
nginx    200 www-data 6u IPv6  34567      0t0  TCP [::]:80 (LISTEN)
```

`Fixtures/lsof_no_process.txt` (권한 부족 시 — 빈 PID/USER 컬럼이 발생할 수 있어 간단 케이스):

```
COMMAND  PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
-        -   -    3u IPv4 0      0t0      TCP 0.0.0.0:3000 (LISTEN)
```

- [ ] **Step 2: 실패 테스트 추가**

```swift
func test_parseLsof_typical_threePorts() {
    let ports = ScanOutputParser.parseLsof(fixture("lsof_typical"))
    XCTAssertEqual(ports.count, 3)
    XCTAssertTrue(ports.contains { $0.port == 22 && $0.processName == "sshd" })
    XCTAssertTrue(ports.contains { $0.port == 5432 && $0.processName == "postgres" })
}

func test_parseLsof_noProcess_treatsDashAsNil() {
    let ports = ScanOutputParser.parseLsof(fixture("lsof_no_process"))
    XCTAssertEqual(ports.count, 1)
    XCTAssertEqual(ports.first?.port, 3000)
    XCTAssertNil(ports.first?.processName)
}
```

- [ ] **Step 3: 실패 확인**

- [ ] **Step 4: 구현 추가**

`ScanOutputParser.swift`에 추가:

```swift
static func parseLsof(_ output: String) -> [RemotePort] {
    var results: [RemotePort] = []
    let lines = output.components(separatedBy: .newlines)
    for (idx, raw) in lines.enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if idx == 0 && line.uppercased().hasPrefix("COMMAND") { continue }
        guard line.contains("(LISTEN)") else { continue }

        let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // 형식: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (LISTEN)
        // NAME 칼럼은 보통 8번 인덱스부터 시작
        guard cols.count >= 10 else { continue }
        let command = cols[0]
        let name = cols[8]
        let processName = command == "-" ? nil : command

        // NAME: "*:22", "127.0.0.1:5432", "[::]:80"
        let normalized = name.replacingOccurrences(of: "*", with: "0.0.0.0")
        guard let (addr, port) = splitAddressPort(normalized) else { continue }
        results.append(RemotePort(port: port, address: addr, processName: processName))
    }
    return results
}
```

- [ ] **Step 5: 통과 → 커밋**

```bash
git add -A
git commit -m "feat(scanning): parseLsof typical + no-process cases"
```

---

### Task 14: `PortScanner` 오케스트레이션

**Files:**
- Create: `PortBridge/Scanning/PortScanner.swift`
- Test: `PortBridgeTests/PortScannerTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

`PortBridgeTests/PortScannerTests.swift`:

```swift
import XCTest
@testable import PortBridge

final class PortScannerTests: XCTestCase {
    func test_ssSuccess_returnsParsedPorts() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*\nLISTEN 0 100 127.0.0.1:5432 0.0.0.0:*",
                stderr: ""
            )
        ]
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(host: "prod")
        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains { $0.port == 3000 })
        XCTAssertTrue(ports.contains { $0.port == 5432 })
    }

    func test_filtersOutOfRangePorts() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(
                exitCode: 0,
                stdout: "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:3000 0.0.0.0:*",
                stderr: ""
            )
        ]
        let scanner = PortScanner(runner: mock)
        let ports = try await scanner.scan(host: "prod", range: 1000...65535)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
    }

    func test_authFailedStderr_throwsAuthError() async throws {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
        ]
        let scanner = PortScanner(runner: mock)
        do {
            _ = try await scanner.scan(host: "prod")
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .sshAuthFailed(host: "prod"))
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

- [ ] **Step 3: 구현**

`PortBridge/Scanning/PortScanner.swift`:

```swift
import Foundation

struct PortScanner {
    let runner: CommandRunner
    let sshExecutable: String = "/usr/bin/ssh"

    func scan(host: String, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
        let remoteCommand = "ss -tlnH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"
        let args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            host,
            remoteCommand
        ]

        let result = try await runner.run(sshExecutable, args: args, timeout: 15)

        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("permission denied") || stderr.contains("publickey") {
                throw PortBridgeError.sshAuthFailed(host: host)
            }
            if stderr.contains("connection timed out") || stderr.contains("connect timeout") {
                throw PortBridgeError.sshConnectTimeout(host: host)
            }
            if result.stdout.isEmpty {
                throw PortBridgeError.remoteCommandNotFound
            }
        }

        // ss 출력은 LISTEN으로 시작, lsof는 헤더 또는 COMMAND PID로 시작
        let first = result.stdout.components(separatedBy: .newlines).first ?? ""
        let parsed: [RemotePort]
        if first.uppercased().hasPrefix("LISTEN") || first.contains("State") {
            parsed = ScanOutputParser.parseSS(result.stdout)
        } else {
            parsed = ScanOutputParser.parseLsof(result.stdout)
        }

        let deduped = Array(Set(parsed))
        return deduped
            .filter { range.contains($0.port) }
            .sorted { $0.port < $1.port }
    }
}
```

- [ ] **Step 4: 통과 → 커밋**

```bash
git add -A
git commit -m "feat(scanning): PortScanner orchestrates ss/lsof via SSH"
```

---

## Phase 6: 터널 관리 (통합 영역, 수동 검증 중심)

### Task 15: `TunnelManager` 기본 구조

**Files:**
- Create: `PortBridge/Tunneling/TunnelManager.swift`

이 단계부터는 `Process` 라이프사이클이 핵심이라 자동 테스트보다 **수동 QA**가 중요하다. 빌드 통과를 1차 검증으로 사용한다.

- [ ] **Step 1: 구조 작성**

`PortBridge/Tunneling/TunnelManager.swift`:

```swift
import Foundation

@MainActor
final class TunnelManager {
    private(set) var active: [UUID: ActiveTunnel] = [:]

    weak var delegate: TunnelManagerDelegate?

    func start(host: String, remotePort: Int, localPort: Int) async throws -> Forwarding {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-L", "\(localPort):localhost:\(remotePort)",
            host
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        let stderrBuffer = StderrRingBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            stderrBuffer.append(data)
        }

        try process.run()

        // 시작 검증: 2초 살아남으면 정상
        try await Task.sleep(nanoseconds: 2_000_000_000)
        if !process.isRunning {
            let stderr = stderrBuffer.snapshot()
            throw PortBridgeError.forwardingDiedEarly(stderr: stderr)
        }

        let forwarding = Forwarding(host: host, remotePort: remotePort, localPort: localPort, state: .active)
        let tunnel = ActiveTunnel(process: process, forwarding: forwarding, stderr: stderrBuffer)
        active[forwarding.id] = tunnel

        // 모니터 Task
        let id = forwarding.id
        tunnel.monitorTask = Task { [weak self] in
            await Self.waitForExit(process)
            await self?.handleTunnelExit(id: id)
        }

        return forwarding
    }

    func stop(_ id: UUID) {
        guard let tunnel = active[id] else { return }
        tunnel.monitorTask?.cancel()
        tunnel.process.terminate()
        active.removeValue(forKey: id)
    }

    func shutdownAll() {
        for (_, tunnel) in active {
            tunnel.monitorTask?.cancel()
            tunnel.process.terminate()
        }
        // SIGTERM 후 짧게 wait
        for (_, tunnel) in active {
            tunnel.process.waitUntilExit()
        }
        active.removeAll()
    }

    private func handleTunnelExit(id: UUID) {
        guard let tunnel = active[id] else { return }
        let stderr = tunnel.stderr.snapshot()
        active.removeValue(forKey: id)
        delegate?.tunnelDidExit(id: id, stderr: stderr)
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                cont.resume()
            }
            if !process.isRunning {
                process.terminationHandler = nil
                cont.resume()
            }
        }
    }
}

protocol TunnelManagerDelegate: AnyObject {
    func tunnelDidExit(id: UUID, stderr: String) async
}

final class ActiveTunnel {
    let process: Process
    var forwarding: Forwarding
    let stderr: StderrRingBuffer
    var monitorTask: Task<Void, Never>?

    init(process: Process, forwarding: Forwarding, stderr: StderrRingBuffer) {
        self.process = process
        self.forwarding = forwarding
        self.stderr = stderr
    }
}

final class StderrRingBuffer: @unchecked Sendable {
    private let maxBytes = 4 * 1024
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer.removeFirst(buffer.count - maxBytes)
        }
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 2: 빌드 통과 확인**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "feat(tunneling): TunnelManager with stderr ring buffer + monitor task"
```

---

## Phase 7: ViewModel & UI

### Task 16: `AppViewModel` 스켈레톤

**Files:**
- Create: `PortBridge/ViewModels/AppViewModel.swift`

- [ ] **Step 1: 작성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    var hosts: [SSHHost] = []
    var selectedHost: SSHHost?
    var ports: [RemotePort] = []
    var searchText: String = ""
    var forwardings: [Forwarding] = []
    var isScanning: Bool = false
    var lastError: String?
    var pendingPortConflict: PortConflict?

    private let parser: () throws -> [SSHHost]
    private let scanner: PortScanner
    private let tunnels: TunnelManager

    init(
        parser: @escaping () throws -> [SSHHost] = { try SSHConfigParser.parse() },
        scanner: PortScanner = PortScanner(runner: ProcessCommandRunner()),
        tunnels: TunnelManager = TunnelManager()
    ) {
        self.parser = parser
        self.scanner = scanner
        self.tunnels = tunnels
        self.tunnels.delegate = self
    }

    var filteredPorts: [RemotePort] {
        guard !searchText.isEmpty else { return ports }
        let q = searchText.lowercased()
        return ports.filter {
            String($0.port).contains(q) ||
            ($0.processName?.lowercased().contains(q) ?? false)
        }
    }

    func loadHosts() {
        do {
            hosts = try parser()
        } catch let error as PortBridgeError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scan() async {
        guard let host = selectedHost else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            ports = try await scanner.scan(host: host.name)
        } catch let error as PortBridgeError {
            lastError = error.errorDescription
            ports = []
        } catch {
            lastError = error.localizedDescription
            ports = []
        }
    }

    func toggleForwarding(for port: RemotePort) async {
        guard let host = selectedHost else { return }
        if let existing = forwardings.first(where: { $0.host == host.name && $0.remotePort == port.port }) {
            tunnels.stop(existing.id)
            forwardings.removeAll { $0.id == existing.id }
            return
        }
        await startForwarding(host: host.name, remotePort: port.port, localPort: port.port)
    }

    func resolveConflict(with newLocalPort: Int) async {
        guard let pending = pendingPortConflict else { return }
        pendingPortConflict = nil
        await startForwarding(host: pending.host, remotePort: pending.remotePort, localPort: newLocalPort)
    }

    private func startForwarding(host: String, remotePort: Int, localPort: Int) async {
        do {
            let fw = try await tunnels.start(host: host, remotePort: remotePort, localPort: localPort)
            forwardings.append(fw)
        } catch PortBridgeError.forwardingDiedEarly(let stderr) where stderr.lowercased().contains("address already in use") {
            pendingPortConflict = PortConflict(host: host, remotePort: remotePort, attemptedLocal: localPort)
        } catch let error as PortBridgeError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct PortConflict: Identifiable, Equatable {
    let id = UUID()
    let host: String
    let remotePort: Int
    let attemptedLocal: Int
}

extension AppViewModel: TunnelManagerDelegate {
    nonisolated func tunnelDidExit(id: UUID, stderr: String) async {
        await MainActor.run {
            if let idx = forwardings.firstIndex(where: { $0.id == id }) {
                forwardings[idx].state = .error(stderr)
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 통과 → 커밋**

```bash
git add -A
git commit -m "feat(viewmodel): AppViewModel skeleton with state hub and forwarding flow"
```

---

### Task 17: `HostPickerView`

**Files:**
- Create: `PortBridge/Views/HostPickerView.swift`

- [ ] **Step 1: 작성**

```swift
import SwiftUI

struct HostPickerView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        HStack {
            Picker("호스트", selection: $vm.selectedHost) {
                Text("선택…").tag(SSHHost?.none)
                ForEach(vm.hosts) { host in
                    Text(host.name).tag(SSHHost?.some(host))
                }
            }
            .frame(maxWidth: 300)

            Button("스캔") {
                Task { await vm.scan() }
            }
            .disabled(vm.selectedHost == nil || vm.isScanning)

            if vm.isScanning {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
```

- [ ] **Step 2: 빌드 → 커밋**

```bash
git add -A
git commit -m "feat(views): HostPickerView"
```

---

### Task 18: `PortListView` + 검색 필터

**Files:**
- Create: `PortBridge/Views/PortListView.swift`
- Create: `PortBridge/Views/ForwardingRowView.swift`

- [ ] **Step 1: 작성**

`PortBridge/Views/ForwardingRowView.swift`:

```swift
import SwiftUI

struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let onToggle: () -> Void

    private var statusIcon: String {
        switch forwarding?.state {
        case .active: return "🟢"
        case .starting: return "🟡"
        case .error: return "🔴"
        case .idle, .none: return "⚪️"
        }
    }

    var body: some View {
        HStack {
            Text(statusIcon)
            VStack(alignment: .leading) {
                Text("\(port.port)")
                    .font(.system(.body, design: .monospaced))
                Text("\(port.address) · \(port.processName ?? "-")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .error(let msg) = forwarding?.state {
                Text(msg.prefix(80))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Toggle("", isOn: Binding(
                get: { forwarding?.state == .active || forwarding?.state == .starting },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
```

`PortBridge/Views/PortListView.swift`:

```swift
import SwiftUI

struct PortListView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("포트 또는 프로세스 검색", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(vm.filteredPorts) { port in
                ForwardingRowView(
                    port: port,
                    forwarding: vm.forwardings.first {
                        $0.remotePort == port.port && $0.host == vm.selectedHost?.name
                    },
                    onToggle: { Task { await vm.toggleForwarding(for: port) } }
                )
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 → 커밋**

```bash
git add -A
git commit -m "feat(views): PortListView with search + ForwardingRowView with toggle"
```

---

### Task 19: `ContentView` 와이어링

**Files:**
- Modify: `PortBridge/ContentView.swift`

- [ ] **Step 1: 작성**

기존 ContentView 전체를 아래로 교체:

```swift
import SwiftUI

struct ContentView: View {
    @State private var vm = AppViewModel()

    var body: some View {
        VStack(spacing: 12) {
            HostPickerView(vm: vm)
            Divider()
            if vm.hosts.isEmpty {
                ContentUnavailableView(
                    "~/.ssh/config 호스트 없음",
                    systemImage: "network.slash",
                    description: Text(vm.lastError ?? "SSH config을 확인하세요.")
                )
            } else {
                PortListView(vm: vm)
            }
            if let err = vm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(minWidth: 600, minHeight: 500)
        .task { vm.loadHosts() }
        .sheet(item: $vm.pendingPortConflict) { conflict in
            PortConflictSheet(conflict: conflict) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
        }
    }
}

struct PortConflictSheet: View {
    let conflict: PortConflict
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var localPortText: String

    init(conflict: PortConflict, onConfirm: @escaping (Int) -> Void) {
        self.conflict = conflict
        self.onConfirm = onConfirm
        _localPortText = State(initialValue: String(conflict.attemptedLocal + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다")
                .font(.headline)
            Text("다른 로컬 포트를 입력하세요. 리모트는 \(conflict.host):\(conflict.remotePort).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("로컬 포트", text: $localPortText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("연결") {
                    if let port = Int(localPortText) {
                        onConfirm(port)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: 빌드 → 커밋**

```bash
git add -A
git commit -m "feat(views): ContentView wires HostPicker + PortList + conflict sheet"
```

---

### Task 20: 앱 종료 시 터널 정리

**Files:**
- Modify: `PortBridge/PortBridgeApp.swift`

- [ ] **Step 1: 작성**

`PortBridgeApp.swift` 교체:

```swift
import SwiftUI
import AppKit

@main
struct PortBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(delegate.viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AppViewModel()

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            viewModel.shutdownAll()
        }
    }
}
```

`AppViewModel.swift`에 메서드 추가:

```swift
func shutdownAll() {
    tunnels.shutdownAll()
    forwardings.removeAll()
}
```

`ContentView.swift`의 `@State private var vm = AppViewModel()` 라인을 다음으로 교체:

```swift
@Environment(AppViewModel.self) private var vm
```

그리고 `task { vm.loadHosts() }` 만 남기고 그대로 사용.

- [ ] **Step 2: 빌드 → 커밋**

```bash
git add -A
git commit -m "feat(app): applicationWillTerminate cleanly shuts down tunnels"
```

---

## Phase 8: 통합 & 수동 QA

### Task 21: 통합 빌드 & 실행 점검

- [ ] **Step 1: 클린 빌드**

```bash
cd ~/datamaker/PortBridge
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' clean build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: 전체 테스트 실행**

```bash
xcodebuild -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: 모든 단위 테스트 통과.

- [ ] **Step 3: Xcode에서 Run (⌘R)으로 앱 실행**

수동 QA 체크리스트 (spec §7.3):

- [ ] ssh config의 호스트가 드롭다운에 나타남, 와일드카드 엔트리는 제외
- [ ] 잘못된 호스트 선택 시 명확한 에러 표시
- [ ] 정상 호스트 스캔 시 포트가 표시됨
- [ ] 검색어 입력 시 즉시 필터링
- [ ] 토글 ON → 다른 터미널에서 `ps aux | grep "ssh -N -L"` 로 프로세스 확인, 로컬 포트로 실제 접속 가능
- [ ] 토글 OFF → 1초 안에 SSH 프로세스 종료
- [ ] 로컬 포트 점유 상태에서 토글 → 다이얼로그가 뜨고 다른 포트로 성공 (예: `nc -l 8080 &` 로 점유 후 8080 포워딩 시도)
- [ ] 앱 ⌘Q 종료 → `ps aux | grep ssh` 로 SSH 프로세스 잔존 확인 (없어야 함)
- [ ] 리모트 서버 일시 다운 → 약 45초 내 행 상태가 🔴 에러로 전환

- [ ] **Step 4: QA 결과를 git에 기록**

발견한 이슈는 docs/ 아래에 메모로 추가하거나 GitHub issue로 등록.

```bash
git status
```

QA 통과 시 README 업데이트:

```bash
cat >> README.md <<'EOF'

## Status
- Phase 1~8 구현 완료. 수동 QA 통과 (YYYY-MM-DD).
EOF
git add README.md
git commit -m "docs: mark v0.1 manual QA passed"
```

---

## Self-Review 메모 (작성자용)

이 계획은 다음을 커버:
- ✅ Spec §3 디렉토리 구조 → Task 1~2
- ✅ Spec §4.1 SSHConfigParser → Task 7~9 (기본/와일드카드/Include)
- ✅ Spec §4.2 CommandRunner → Task 10~11
- ✅ Spec §4.3 PortScanner → Task 12~14
- ✅ Spec §4.4 TunnelManager → Task 15
- ✅ Spec §4.5 AppViewModel → Task 16
- ✅ Spec §5 데이터 흐름 → Task 16~20 통합
- ✅ Spec §6 에러 처리 → Task 6 (enum) + Task 16 (배너/시트) + Task 18 (행 상태)
- ✅ Spec §7 테스트 → Task 3~14 단위테스트 + Task 21 수동 QA
- ✅ Spec §2 Decisions의 모든 항목 (BatchMode, ExitOnForwardFailure, ServerAlive*, ss→lsof 폴백, 와일드카드 제외, Include 재귀)

알려진 제한:
- Xcode 프로젝트 생성(Task 1)은 GUI 작업이 필요 — CLI 자동화 불가.
- Process 라이프사이클 자동 테스트 없음 (의도된 trade-off, Task 21 수동 QA로 검증).
- `applicationWillTerminate` 는 force-quit 시 호출 보장이 없음 — 좀비 SSH가 남을 수 있는 케이스로, 차후 launchd plist 또는 별도 sentinel 프로세스로 보완 가능 (현재 범위 밖).
