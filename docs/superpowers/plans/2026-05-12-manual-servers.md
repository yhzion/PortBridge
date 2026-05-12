# Manual Server Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSH 서버를 `~/.ssh/config`에서 자동으로 읽어오는 방식을 폐기하고, 사용자가 직접 서버를 등록·관리하는 방식으로 전환한다.

**Architecture:** `ServerStore`가 UserDefaults에 서버 목록을 영속화한다. 각 서버는 독립적인 `ServerSectionViewModel`을 가져 스캔 상태를 자체 관리한다. `AppViewModel`은 `serverSections[]`와 `forwardings[]`를 소유하며 `TunnelManager`에 SSH 포워딩을 위임한다.

**Tech Stack:** Swift 5.9+, SwiftUI, `@Observable` (Observation framework), XCTest, xcodebuild

**Note:** 이 프로젝트는 `PBXFileSystemSynchronizedRootGroup`을 사용하므로 새 `.swift` 파일을 디렉토리에 두면 **자동으로 빌드 타겟에 포함**된다. `project.pbxproj` 수동 편집 불필요.

---

## 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `PortBridge/Models/Server.swift` | 신규 |
| `PortBridge/Models/Forwarding.swift` | `host→serverId+serverDisplayName` |
| `PortBridge/Models/PortBridgeError.swift` | sshConfig 관련 케이스 2개 삭제 |
| `PortBridge/Storage/ServerStore.swift` | 신규 |
| `PortBridge/Scanning/PortScanner.swift` | `scan(server:)` |
| `PortBridge/Tunneling/TunnelManager.swift` | `start(server:)` |
| `PortBridge/ViewModels/ServerSectionViewModel.swift` | 신규 |
| `PortBridge/ViewModels/AppViewModel.swift` | 전면 재작성 |
| `PortBridge/Views/AddServerSheet.swift` | 신규 |
| `PortBridge/Views/ServerSectionView.swift` | 신규 |
| `PortBridge/Views/ServerListView.swift` | 신규 |
| `PortBridge/ContentView.swift` | 수정 |
| `PortBridge/Views/ForwardingRowView.swift` | 서버 이름 pill 추가 |
| `PortBridgeTests/ServerTests.swift` | 신규 |
| `PortBridgeTests/ServerStoreTests.swift` | 신규 |
| `PortBridgeTests/ServerSectionViewModelTests.swift` | 신규 |
| `PortBridgeTests/ForwardingTests.swift` | 수정 |
| `PortBridgeTests/PortScannerTests.swift` | 수정 |
| `PortBridge/Models/SSHHost.swift` | **삭제** |
| `PortBridge/SSH/SSHConfigParser.swift` | **삭제** |
| `PortBridge/Views/HostPickerView.swift` | **삭제** |
| `PortBridge/Views/PortListView.swift` | **삭제** |
| `PortBridgeTests/SSHHostTests.swift` | **삭제** |
| `PortBridgeTests/SSHConfigParserTests.swift` | **삭제** |

**테스트 실행 명령어 (각 Task 완료 후 사용):**
```bash
xcodebuild test \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(Test.*passed|Test.*failed|error:|Build succeeded|Build FAILED|Executed)" | tail -30
```

---

## Task 1: Server 모델

**Files:**
- Create: `PortBridge/Models/Server.swift`
- Create: `PortBridgeTests/ServerTests.swift`
- Delete: `PortBridgeTests/SSHHostTests.swift` (Task 1 완료 후 삭제)

- [ ] **Step 1: 테스트 파일 작성 (실패 확인용)**

```swift
// PortBridgeTests/ServerTests.swift
import XCTest
@testable import PortBridge

final class ServerTests: XCTestCase {
    func test_displayName_withName_showsNameAndHost() {
        let s = Server(name: "prod", user: "ubuntu", host: "10.0.0.1")
        XCTAssertEqual(s.displayName, "prod (10.0.0.1)")
    }

    func test_displayName_withoutName_showsHostOnly() {
        let s = Server(name: nil, user: "ubuntu", host: "10.0.0.1")
        XCTAssertEqual(s.displayName, "10.0.0.1")
    }

    func test_sshTarget_combinesUserAndHost() {
        let s = Server(user: "deploy", host: "192.168.1.5")
        XCTAssertEqual(s.sshTarget, "deploy@192.168.1.5")
    }

    func test_defaultPort_is22() {
        let s = Server(user: "u", host: "h")
        XCTAssertEqual(s.port, 22)
    }

    func test_codable_roundtrip() throws {
        let s = Server(name: "test", user: "u", host: "h", port: 2222)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        XCTAssertEqual(s, decoded)
    }
}
```

- [ ] **Step 2: 테스트 실행 — 빌드 실패 확인**

```
Expected: error: cannot find type 'Server' in scope
```

- [ ] **Step 3: Server 모델 구현**

```swift
// PortBridge/Models/Server.swift
import Foundation

struct Server: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String?
    var user: String
    var host: String
    var port: Int

    init(id: UUID = UUID(), name: String? = nil, user: String, host: String, port: Int = 22) {
        self.id = id
        self.name = name
        self.user = user
        self.host = host
        self.port = port
    }

    var displayName: String {
        name.map { "\($0) (\(host))" } ?? host
    }

    var sshTarget: String { "\(user)@\(host)" }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

```
Expected: Test Suite 'ServerTests' passed.
```

- [ ] **Step 5: SSHHostTests 삭제**

```bash
rm PortBridgeTests/SSHHostTests.swift
```

- [ ] **Step 6: 커밋**

```bash
git add PortBridge/Models/Server.swift PortBridgeTests/ServerTests.swift PortBridgeTests/SSHHostTests.swift
git commit -m "feat(model): add Server struct, replace SSHHost"
```

---

## Task 2: Forwarding 모델 업데이트

**Files:**
- Modify: `PortBridge/Models/Forwarding.swift`
- Modify: `PortBridgeTests/ForwardingTests.swift`

- [ ] **Step 1: ForwardingTests 업데이트**

```swift
// PortBridgeTests/ForwardingTests.swift
import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    private let serverId = UUID()

    func test_idUnique() {
        let a = Forwarding(serverId: serverId, serverDisplayName: "prod", remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(serverId: serverId, serverDisplayName: "prod", remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }

    func test_serverDisplayName_preserved() {
        let fw = Forwarding(serverId: serverId, serverDisplayName: "prod (10.0.0.1)", remotePort: 5432, localPort: 5432, state: .active)
        XCTAssertEqual(fw.serverDisplayName, "prod (10.0.0.1)")
    }
}
```

- [ ] **Step 2: Forwarding 모델 수정**

```swift
// PortBridge/Models/Forwarding.swift
import Foundation

struct Forwarding: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case starting
        case active
        case error(String)
    }

    let id: UUID
    let serverId: UUID
    let serverDisplayName: String
    let remotePort: Int
    var localPort: Int
    var state: State

    init(
        id: UUID = UUID(),
        serverId: UUID,
        serverDisplayName: String,
        remotePort: Int,
        localPort: Int,
        state: State
    ) {
        self.id = id
        self.serverId = serverId
        self.serverDisplayName = serverDisplayName
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
    }
}
```

- [ ] **Step 3: 테스트 실행 — 통과 확인**

```
Expected: Test Suite 'ForwardingTests' passed.
```

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Models/Forwarding.swift PortBridgeTests/ForwardingTests.swift
git commit -m "feat(model): update Forwarding — host→serverId+serverDisplayName"
```

---

## Task 3: PortBridgeError 정리

**Files:**
- Modify: `PortBridge/Models/PortBridgeError.swift`

- [ ] **Step 1: sshConfig 관련 케이스 2개 삭제**

`sshConfigNotFound`와 `sshConfigUnreadable`을 제거한다. `SSHConfigParser`가 삭제되므로 이 케이스들은 더 이상 throw되지 않는다.

```swift
// PortBridge/Models/PortBridgeError.swift
import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)
    case remoteCommandNotFound
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

- [ ] **Step 2: SSHConfigParserTests 삭제**

```bash
rm PortBridgeTests/SSHConfigParserTests.swift
```

- [ ] **Step 3: 테스트 실행 — 통과 확인**

```
Expected: Build succeeded (기존 테스트들 모두 통과)
```

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Models/PortBridgeError.swift PortBridgeTests/SSHConfigParserTests.swift
git commit -m "refactor: remove sshConfig error cases — SSHConfigParser 폐기"
```

---

## Task 4: ServerStore

**Files:**
- Create: `PortBridge/Storage/ServerStore.swift`
- Create: `PortBridgeTests/ServerStoreTests.swift`

- [ ] **Step 1: 테스트 파일 작성**

```swift
// PortBridgeTests/ServerStoreTests.swift
import XCTest
@testable import PortBridge

final class ServerStoreTests: XCTestCase {
    private let testKey = "portbridge.servers"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    func test_add_appendsServer() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.add(s)
        XCTAssertEqual(store.servers.count, 1)
        XCTAssertEqual(store.servers.first?.id, s.id)
    }

    func test_update_modifiesExisting() {
        let store = ServerStore()
        var s = Server(user: "u", host: "h")
        store.add(s)
        s.name = "updated"
        store.update(s)
        XCTAssertEqual(store.servers.first?.name, "updated")
    }

    func test_delete_removesServer() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.add(s)
        store.delete(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_persistence_survivesNewInstance() {
        let s = Server(name: "prod", user: "ubuntu", host: "10.0.0.1")
        let store1 = ServerStore()
        store1.add(s)

        let store2 = ServerStore()
        XCTAssertEqual(store2.servers.first?.id, s.id)
        XCTAssertEqual(store2.servers.first?.name, "prod")
    }

    func test_update_unknownId_doesNothing() {
        let store = ServerStore()
        let s = Server(user: "u", host: "h")
        store.update(s)
        XCTAssertTrue(store.servers.isEmpty)
    }

    func test_order_preserved() {
        let store = ServerStore()
        let a = Server(user: "u", host: "a")
        let b = Server(user: "u", host: "b")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.servers.map(\.host), ["a", "b"])
    }
}
```

- [ ] **Step 2: 빌드 실패 확인**

```
Expected: error: cannot find type 'ServerStore' in scope
```

- [ ] **Step 3: ServerStore 구현**

```swift
// PortBridge/Storage/ServerStore.swift
import Foundation
import Observation

@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    private let defaultsKey = "portbridge.servers"

    init() {
        load()
    }

    func add(_ server: Server) {
        servers.append(server)
        save()
    }

    func update(_ server: Server) {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[idx] = server
        save()
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return }
        servers = decoded
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

```
Expected: Test Suite 'ServerStoreTests' passed.
```

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/Storage/ServerStore.swift PortBridgeTests/ServerStoreTests.swift
git commit -m "feat: add ServerStore — UserDefaults 기반 서버 목록 영속화"
```

---

## Task 5: PortScanner 업데이트

**Files:**
- Modify: `PortBridge/Scanning/PortScanner.swift`
- Modify: `PortBridgeTests/PortScannerTests.swift`

- [ ] **Step 1: 테스트 파일 업데이트**

```swift
// PortBridgeTests/PortScannerTests.swift
import XCTest
@testable import PortBridge

final class PortScannerTests: XCTestCase {
    private func makeServer(user: String = "ubuntu", host: String = "prod", port: Int = 22) -> Server {
        Server(user: user, host: host, port: port)
    }

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
        let ports = try await scanner.scan(server: makeServer())
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
        let ports = try await scanner.scan(server: makeServer(), range: 1000...65535)
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
            _ = try await scanner.scan(server: makeServer())
            XCTFail("expected throw")
        } catch let error as PortBridgeError {
            XCTAssertEqual(error, .sshAuthFailed(host: "prod"))
        }
    }

    func test_sshArgs_includePortAndTarget() async throws {
        let mock = MockCommandRunner()
        mock.responses = [CommandResult(exitCode: 0, stdout: "", stderr: "")]
        let scanner = PortScanner(runner: mock)
        let server = Server(user: "deploy", host: "10.0.0.1", port: 2222)
        _ = try await scanner.scan(server: server)
        let args = mock.calls.first?.args ?? []
        XCTAssertTrue(args.contains("-p"), "args should contain -p flag")
        XCTAssertTrue(args.contains("2222"), "args should contain port")
        XCTAssertTrue(args.contains("deploy@10.0.0.1"), "args should contain user@host")
    }
}
```

- [ ] **Step 2: PortScanner 수정**

```swift
// PortBridge/Scanning/PortScanner.swift
import Foundation

struct PortScanner {
    let runner: CommandRunner
    let sshExecutable: String = "/usr/bin/ssh"

    func scan(server: Server, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
        let remoteCommand = "ss -tlnH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"
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
            if stderr.contains("connection timed out") || stderr.contains("connect timeout") {
                throw PortBridgeError.sshConnectTimeout(host: server.host)
            }
            if result.stdout.isEmpty {
                throw PortBridgeError.remoteCommandNotFound
            }
        }

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

- [ ] **Step 3: 테스트 실행 — 통과 확인**

```
Expected: Test Suite 'PortScannerTests' passed.
```

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Scanning/PortScanner.swift PortBridgeTests/PortScannerTests.swift
git commit -m "feat(scanner): scan(server:) — -p port + user@host 형식"
```

---

## Task 6: TunnelManager 업데이트

**Files:**
- Modify: `PortBridge/Tunneling/TunnelManager.swift`

- [ ] **Step 1: `start(server:)` 시그니처로 변경**

`start(host: String, ...)` → `start(server: Server, ...)`. `Forwarding` 생성 시 `serverId`와 `serverDisplayName`을 사용.

```swift
// PortBridge/Tunneling/TunnelManager.swift
import Foundation

@MainActor
final class TunnelManager {
    private(set) var active: [UUID: ActiveTunnel] = [:]
    weak var delegate: TunnelManagerDelegate?

    func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-p", "\(server.port)",
            "-L", "\(localPort):localhost:\(remotePort)",
            server.sshTarget
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

        try await Task.sleep(nanoseconds: 2_000_000_000)
        if !process.isRunning {
            let stderr = stderrBuffer.snapshot()
            throw PortBridgeError.forwardingDiedEarly(stderr: stderr)
        }

        let forwarding = Forwarding(
            serverId: server.id,
            serverDisplayName: server.displayName,
            remotePort: remotePort,
            localPort: localPort,
            state: .active
        )
        let tunnel = ActiveTunnel(process: process, forwarding: forwarding, stderr: stderrBuffer)
        active[forwarding.id] = tunnel

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
        for (_, tunnel) in active {
            tunnel.process.waitUntilExit()
        }
        active.removeAll()
    }

    private func handleTunnelExit(id: UUID) async {
        guard let tunnel = active[id] else { return }
        let stderr = tunnel.stderr.snapshot()
        active.removeValue(forKey: id)
        await delegate?.tunnelDidExit(id: id, stderr: stderr)
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
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

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -10
```

Expected: `Build succeeded` 또는 AppViewModel 관련 에러만 (다음 Task에서 수정)

- [ ] **Step 3: 커밋**

```bash
git add PortBridge/Tunneling/TunnelManager.swift
git commit -m "feat(tunnel): start(server:) — -p port + user@host 지원"
```

---

## Task 7: ServerSectionViewModel

**Files:**
- Create: `PortBridge/ViewModels/ServerSectionViewModel.swift`
- Create: `PortBridgeTests/ServerSectionViewModelTests.swift`

- [ ] **Step 1: 테스트 파일 작성**

```swift
// PortBridgeTests/ServerSectionViewModelTests.swift
import XCTest
@testable import PortBridge

final class ServerSectionViewModelTests: XCTestCase {
    private func makeServer() -> Server {
        Server(user: "ubuntu", host: "10.0.0.1")
    }

    @MainActor
    func test_initialState_isIdle() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertEqual(vm.scanState, .idle)
    }

    @MainActor
    func test_scan_success_setsLoaded() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 0, stdout: "LISTEN 0 128 0.0.0.0:3000 0.0.0.0:*", stderr: "")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .loaded(let ports) = vm.scanState else {
            XCTFail("expected .loaded, got \(vm.scanState)"); return
        }
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 3000)
    }

    @MainActor
    func test_scan_authFailed_setsAuthFailed() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .authFailed(let cmd) = vm.scanState else {
            XCTFail("expected .authFailed, got \(vm.scanState)"); return
        }
        XCTAssertTrue(cmd.contains("ssh-copy-id"))
        XCTAssertTrue(cmd.contains("ubuntu@10.0.0.1"))
    }

    @MainActor
    func test_scan_connectTimeout_setsError() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 255, stdout: "", stderr: "Connection timed out")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        guard case .error = vm.scanState else {
            XCTFail("expected .error, got \(vm.scanState)"); return
        }
    }

    @MainActor
    func test_ports_whenLoaded_returnsPorts() async {
        let mock = MockCommandRunner()
        mock.responses = [
            CommandResult(exitCode: 0, stdout: "LISTEN 0 128 0.0.0.0:8080 0.0.0.0:*", stderr: "")
        ]
        let vm = ServerSectionViewModel(server: makeServer(), scanner: PortScanner(runner: mock))
        await vm.scan()
        XCTAssertEqual(vm.ports.count, 1)
        XCTAssertEqual(vm.ports.first?.port, 8080)
    }

    @MainActor
    func test_ports_whenIdle_isEmpty() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertTrue(vm.ports.isEmpty)
    }

    @MainActor
    func test_toggleExpanded_flipsValue() {
        let vm = ServerSectionViewModel(server: makeServer())
        XCTAssertTrue(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertFalse(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertTrue(vm.isExpanded)
    }

    @MainActor
    func test_id_equalsServerId() {
        let server = makeServer()
        let vm = ServerSectionViewModel(server: server)
        XCTAssertEqual(vm.id, server.id)
    }
}
```

- [ ] **Step 2: 빌드 실패 확인**

```
Expected: error: cannot find type 'ServerSectionViewModel' in scope
```

- [ ] **Step 3: ServerSectionViewModel 구현**

```swift
// PortBridge/ViewModels/ServerSectionViewModel.swift
import Foundation
import Observation

enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case error(String)
    case authFailed(copyCommand: String)
}

@MainActor
@Observable
final class ServerSectionViewModel: Identifiable {
    let server: Server
    private(set) var scanState: ServerScanState = .idle
    private(set) var isExpanded: Bool = true

    private let scanner: PortScanner

    var id: UUID { server.id }

    init(server: Server, scanner: PortScanner = PortScanner(runner: ProcessCommandRunner())) {
        self.server = server
        self.scanner = scanner
    }

    var ports: [RemotePort] {
        if case .loaded(let ports) = scanState { return ports }
        return []
    }

    func scan() async {
        guard scanState != .scanning else { return }
        scanState = .scanning
        do {
            let loaded = try await scanner.scan(server: server)
            scanState = .loaded(loaded)
        } catch PortBridgeError.sshAuthFailed {
            scanState = .authFailed(copyCommand: "ssh-copy-id \(server.sshTarget)")
        } catch let error as PortBridgeError {
            scanState = .error(error.errorDescription ?? error.localizedDescription)
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

```
Expected: Test Suite 'ServerSectionViewModelTests' passed.
```

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/ViewModels/ServerSectionViewModel.swift PortBridgeTests/ServerSectionViewModelTests.swift
git commit -m "feat(vm): ServerSectionViewModel — 서버별 독립 스캔 상태 관리"
```

---

## Task 8: AppViewModel 재작성

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`

- [ ] **Step 1: AppViewModel 전면 교체**

`PortConflict`도 이 파일로 이동 (ContentView.swift에서 제거됨).

```swift
// PortBridge/ViewModels/AppViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private let store: ServerStore
    private let scanner: PortScanner
    private let tunnels: TunnelManager

    private(set) var serverSections: [ServerSectionViewModel] = []
    var forwardings: [Forwarding] = []
    private(set) var activatedAt: [UUID: Date] = [:]
    var pendingPortConflict: PortConflict?
    var lastError: String?

    init(
        store: ServerStore = ServerStore(),
        scanner: PortScanner = PortScanner(runner: ProcessCommandRunner()),
        tunnels: TunnelManager? = nil
    ) {
        self.store = store
        self.scanner = scanner
        let t = tunnels ?? TunnelManager()
        self.tunnels = t
        t.delegate = self
        rebuildSections()
    }

    var activeForwardings: [Forwarding] {
        forwardings
            .filter { fw in
                switch fw.state {
                case .active, .starting, .error: return true
                case .idle: return false
                }
            }
            .sorted {
                activatedAt[$0.id, default: .distantPast] > activatedAt[$1.id, default: .distantPast]
            }
    }

    // MARK: - Server CRUD

    func addServer(_ server: Server) {
        store.add(server)
        let section = ServerSectionViewModel(server: server, scanner: scanner)
        serverSections.append(section)
        Task { await section.scan() }
    }

    func updateServer(_ server: Server) {
        store.update(server)
        rebuildSections()
    }

    func deleteServer(_ server: Server) {
        stopAll(for: server.id)
        store.delete(server)
        serverSections.removeAll { $0.server.id == server.id }
    }

    // MARK: - Scanning

    func scanAll() async {
        await withTaskGroup(of: Void.self) { group in
            for section in serverSections {
                group.addTask { await section.scan() }
            }
        }
    }

    // MARK: - Forwarding

    func toggleForwarding(serverId: UUID, for port: RemotePort) async {
        if let existing = forwardings.first(where: { $0.serverId == serverId && $0.remotePort == port.port }) {
            tunnels.stop(existing.id)
            activatedAt[existing.id] = nil
            forwardings.removeAll { $0.id == existing.id }
            return
        }
        guard let section = serverSections.first(where: { $0.server.id == serverId }) else { return }
        await startForwarding(server: section.server, remotePort: port.port, localPort: port.port)
    }

    func resolveConflict(with newLocalPort: Int) async {
        guard let pending = pendingPortConflict else { return }
        pendingPortConflict = nil
        guard let section = serverSections.first(where: { $0.server.id == pending.serverId }) else { return }
        await startForwarding(server: section.server, remotePort: pending.remotePort, localPort: newLocalPort)
    }

    func stopAll(for serverId: UUID) {
        let mine = forwardings.filter { $0.serverId == serverId }
        for fw in mine {
            tunnels.stop(fw.id)
            activatedAt[fw.id] = nil
        }
        forwardings.removeAll { $0.serverId == serverId }
    }

    func shutdownAll() {
        tunnels.shutdownAll()
        forwardings.removeAll()
        activatedAt.removeAll()
    }

    // MARK: - Private

    private func rebuildSections() {
        let existing = Dictionary(uniqueKeysWithValues: serverSections.map { ($0.server.id, $0) })
        serverSections = store.servers.map { server in
            existing[server.id] ?? ServerSectionViewModel(server: server, scanner: scanner)
        }
    }

    private func startForwarding(server: Server, remotePort: Int, localPort: Int) async {
        lastError = nil
        let placeholderID = UUID()
        let placeholder = Forwarding(
            id: placeholderID,
            serverId: server.id,
            serverDisplayName: server.displayName,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting
        )
        forwardings.append(placeholder)
        activatedAt[placeholderID] = Date()

        do {
            let fw = try await tunnels.start(server: server, remotePort: remotePort, localPort: localPort)
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
            } else {
                forwardings.append(fw)
            }
            if let ts = activatedAt.removeValue(forKey: placeholderID) {
                activatedAt[fw.id] = ts
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr)
            where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            pendingPortConflict = PortConflict(
                serverId: server.id,
                serverDisplayName: server.displayName,
                remotePort: remotePort,
                attemptedLocal: localPort
            )
        } catch let error as PortBridgeError {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            lastError = error.errorDescription
        } catch {
            forwardings.removeAll { $0.id == placeholderID }
            activatedAt[placeholderID] = nil
            lastError = error.localizedDescription
        }
    }
}

struct PortConflict: Identifiable, Equatable {
    let id = UUID()
    let serverId: UUID
    let serverDisplayName: String
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

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -10
```

Expected: 뷰 파일(ContentView, PortListView 등)에서 에러 발생 — 다음 Task에서 수정

- [ ] **Step 3: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift
git commit -m "feat(vm): AppViewModel 재작성 — serverSections 기반 멀티 서버"
```

---

## Task 9: AddServerSheet

**Files:**
- Create: `PortBridge/Views/AddServerSheet.swift`

- [ ] **Step 1: AddServerSheet 구현**

```swift
// PortBridge/Views/AddServerSheet.swift
import SwiftUI

struct AddServerSheet: View {
    let onSave: (Server) -> Void
    var editing: Server? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var user: String = ""
    @State private var host: String = ""
    @State private var portText: String = "22"

    private var isValid: Bool { !user.trimmingCharacters(in: .whitespaces).isEmpty && !host.trimmingCharacters(in: .whitespaces).isEmpty }
    private var portValue: Int { Int(portText) ?? 22 }

    init(editing: Server? = nil, onSave: @escaping (Server) -> Void) {
        self.editing = editing
        self.onSave = onSave
        if let s = editing {
            _name = State(initialValue: s.name ?? "")
            _user = State(initialValue: s.user)
            _host = State(initialValue: s.host)
            _portText = State(initialValue: "\(s.port)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "서버 추가" : "서버 편집")
                .font(.headline)

            Form {
                TextField("표시 이름 (선택사항)", text: $name)
                TextField("사용자", text: $user)
                    .disableAutocorrection(true)
                TextField("호스트 (IP 또는 hostname)", text: $host)
                    .disableAutocorrection(true)
                TextField("포트", text: $portText)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "추가" : "저장") {
                    let server = Server(
                        id: editing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name.trimmingCharacters(in: .whitespaces),
                        user: user.trimmingCharacters(in: .whitespaces),
                        host: host.trimmingCharacters(in: .whitespaces),
                        port: portValue
                    )
                    onSave(server)
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -10
```

- [ ] **Step 3: 커밋**

```bash
git add PortBridge/Views/AddServerSheet.swift
git commit -m "feat(view): AddServerSheet — 서버 추가/편집 폼"
```

---

## Task 10: ServerSectionView

**Files:**
- Create: `PortBridge/Views/ServerSectionView.swift`

- [ ] **Step 1: ServerSectionView 구현**

```swift
// PortBridge/Views/ServerSectionView.swift
import SwiftUI
import AppKit

struct ServerSectionView: View {
    let section: ServerSectionViewModel
    let activeForwardings: [Forwarding]
    let onToggle: (RemotePort) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var inactivePorts: [RemotePort] {
        let activeNums = Set(
            activeForwardings
                .filter { $0.serverId == section.server.id }
                .map { $0.remotePort }
        )
        return section.ports.filter { !activeNums.contains($0.port) }
    }

    var body: some View {
        Section {
            if section.isExpanded {
                sectionContent
            }
        } header: {
            sectionHeader
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section.scanState {
        case .idle:
            Text("↻ 버튼을 눌러 포트를 스캔하세요")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("스캔 중…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .loaded where inactivePorts.isEmpty:
            Text("포워딩되지 않은 포트 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

        case .loaded:
            ForEach(inactivePorts) { port in
                ForwardingRowView(port: port, forwarding: nil, onToggle: { onToggle(port) })
            }

        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.vertical, 4)

        case .authFailed(let cmd):
            AuthFailedView(copyCommand: cmd) { Task { await section.scan() } }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    section.toggleExpanded()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(section.server.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if case .scanning = section.scanState {
                ProgressView().controlSize(.mini)
            } else {
                Button { Task { await section.scan() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("\(section.server.displayName) 포트 재스캔")
            }

            Menu {
                Button("편집…", action: onEdit)
                Divider()
                Button("삭제", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
    }
}

private struct AuthFailedView: View {
    let copyCommand: String
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("SSH 키 인증 실패", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack(spacing: 8) {
                Text(verbatim: copyCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(copied ? "복사됨 ✓" : "복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyCommand, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(copied ? .green : .tint)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -10
```

- [ ] **Step 3: 커밋**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "feat(view): ServerSectionView — 서버별 섹션 헤더 + 포트 목록"
```

---

## Task 11: ServerListView (PortListView 대체)

**Files:**
- Create: `PortBridge/Views/ServerListView.swift`

- [ ] **Step 1: ServerListView 구현**

```swift
// PortBridge/Views/ServerListView.swift
import SwiftUI

struct ServerListView: View {
    @Bindable var vm: AppViewModel
    @State private var showAddSheet = false
    @State private var editingServer: Server? = nil

    var body: some View {
        List {
            // 포워딩 중 섹션
            if !vm.activeForwardings.isEmpty {
                Section {
                    ForEach(vm.activeForwardings, id: \.id) { fw in
                        activeRow(for: fw)
                    }
                } header: {
                    Text("포워딩 중")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            // 서버별 섹션
            ForEach(vm.serverSections) { section in
                ServerSectionView(
                    section: section,
                    activeForwardings: vm.activeForwardings,
                    onToggle: { port in
                        Task { await vm.toggleForwarding(serverId: section.server.id, for: port) }
                    },
                    onEdit: { editingServer = section.server },
                    onDelete: { vm.deleteServer(section.server) }
                )
            }
        }
        .safeAreaInset(edge: .top) {
            serverListHeader
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeForwardings.map(\.id))
        .sheet(isPresented: $showAddSheet) {
            AddServerSheet { server in vm.addServer(server) }
        }
        .sheet(item: $editingServer) { server in
            AddServerSheet(editing: server) { updated in vm.updateServer(updated) }
        }
    }

    @ViewBuilder
    private func activeRow(for fw: Forwarding) -> some View {
        if let section = vm.serverSections.first(where: { $0.server.id == fw.serverId }),
           let port = section.ports.first(where: { $0.port == fw.remotePort }) {
            ForwardingRowView(
                port: port,
                forwarding: fw,
                onToggle: { Task { await vm.toggleForwarding(serverId: fw.serverId, for: port) } }
            )
        }
    }

    private var serverListHeader: some View {
        HStack {
            Text("서버")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await vm.scanAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("전체 서버 포트 새로고침")

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("서버 추가")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -10
```

- [ ] **Step 3: 커밋**

```bash
git add PortBridge/Views/ServerListView.swift
git commit -m "feat(view): ServerListView — 멀티 서버 포트 목록 (포워딩 중 최상단)"
```

---

## Task 12: ContentView 업데이트 + ForwardingRowView 서버 pill

**Files:**
- Modify: `PortBridge/ContentView.swift`
- Modify: `PortBridge/Views/ForwardingRowView.swift`

- [ ] **Step 1: ForwardingRowView에 서버 이름 pill 추가**

포트 번호 옆에 `serverDisplayName`을 소형 pill로 표시. active 상태인 포워딩 행에서만 필요하다.

`ForwardingRowView.swift`의 프로세스 이름 다음 부분을 수정:

```swift
// PortBridge/Views/ForwardingRowView.swift — body 내 HStack(spacing: 6) 블록 교체
HStack(spacing: 6) {
    Text(verbatim: "포트 " + String(port.port))
        .font(.system(.body, design: .monospaced).weight(.semibold))
    if let proc = port.processName {
        Text(verbatim: proc)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
    if let name = forwarding?.serverDisplayName {
        Text(verbatim: name)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.tint)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
```

- [ ] **Step 2: ContentView 전면 교체**

```swift
// PortBridge/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if vm.serverSections.isEmpty {
                emptyState
            } else {
                Divider()
                ServerListView(vm: vm)
            }

            if let err = vm.lastError {
                errorBanner(err)
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 80, idealHeight: vm.serverSections.isEmpty ? 120 : 480)
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await vm.scanAll() }
        .sheet(item: Binding(
            get: { vm.pendingPortConflict },
            set: { vm.pendingPortConflict = $0 }
        )) { conflict in
            PortConflictSheet(conflict: conflict) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "등록된 서버가 없습니다",
            systemImage: "server.rack",
            description: Text("상단 '+' 버튼으로 SSH 서버를 추가하세요.")
        )
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack {
                Text("서버").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    // emptyState에서는 직접 ServerListView를 쓰지 않으므로
                    // AppViewModel을 통해 sheet 트리거
                } label: {
                    Image(systemName: "plus").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { vm.lastError = nil } label: {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("에러 메시지 닫기")
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
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
            Text(verbatim: "로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다")
                .font(.headline)
            Text(verbatim: "다른 로컬 포트를 입력하세요. 리모트는 \(conflict.serverDisplayName):\(conflict.remotePort).")
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

**Note:** 빈 서버 목록 상태에서의 `+` 버튼 동작은 이 구현에서는 `ServerListView`가 렌더링되지 않아 sheet 트리거가 복잡하다. 가장 단순한 해결책: `emptyState`에 `serverSections.isEmpty`를 체크하는 조건부 `ServerListView`를 숨겨두지 않고, `vm.serverSections.isEmpty`일 때도 `ServerListView`를 항상 표시하되 list가 비어있으면 `ContentUnavailableView`를 내부에서 표시하도록 `ServerListView`를 수정한다.

`ServerListView`의 `body`에 추가:
```swift
// List 위에, ForEach 전에 삽입
if vm.serverSections.isEmpty {
    ContentUnavailableView(
        "등록된 서버가 없습니다",
        systemImage: "server.rack",
        description: Text("'+' 버튼으로 SSH 서버를 추가하세요.")
    )
}
```

그리고 `ContentView`에서 분기를 제거:
```swift
// ContentView.body 단순화
var body: some View {
    VStack(spacing: 0) {
        Divider()
        ServerListView(vm: vm)

        if let err = vm.lastError {
            errorBanner(err)
        }
    }
    .frame(minWidth: 480, idealWidth: 540, minHeight: 80, idealHeight: vm.serverSections.isEmpty ? 200 : 480)
    .frame(maxHeight: .infinity, alignment: .top)
    .task { await vm.scanAll() }
    .sheet(item: Binding(
        get: { vm.pendingPortConflict },
        set: { vm.pendingPortConflict = $0 }
    )) { conflict in
        PortConflictSheet(conflict: conflict) { newPort in
            Task { await vm.resolveConflict(with: newPort) }
        }
    }
}
```

- [ ] **Step 3: 빌드 및 테스트 실행 — 통과 확인**

```bash
xcodebuild test \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(Test.*passed|Test.*failed|error:|Build succeeded|Build FAILED|Executed)" | tail -30
```

Expected: 모든 테스트 통과

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/ContentView.swift PortBridge/Views/ForwardingRowView.swift
git commit -m "feat(view): ContentView + ForwardingRowView 서버 pill — 새 레이아웃 완성"
```

---

## Task 13: 파일 정리 및 최종 확인

**Files:**
- Delete: `PortBridge/Models/SSHHost.swift`
- Delete: `PortBridge/SSH/SSHConfigParser.swift`
- Delete: `PortBridge/Views/HostPickerView.swift`
- Delete: `PortBridge/Views/PortListView.swift`

- [ ] **Step 1: 불필요 파일 삭제**

```bash
rm PortBridge/Models/SSHHost.swift
rm PortBridge/SSH/SSHConfigParser.swift
rm PortBridge/Views/HostPickerView.swift
rm PortBridge/Views/PortListView.swift
```

- [ ] **Step 2: 전체 빌드 및 테스트 실행**

```bash
xcodebuild test \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(Test.*passed|Test.*failed|error:|Build succeeded|Build FAILED|Executed)" | tail -30
```

Expected: 모든 테스트 통과, 삭제된 타입 참조 에러 없음

- [ ] **Step 3: 앱 실행 및 수동 검증**

```bash
xcodebuild build \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "(error:|Build succeeded|Build FAILED)" | tail -5
```

검증 항목:
- [ ] 앱 실행 → "등록된 서버가 없습니다" 표시
- [ ] `+` 버튼 → AddServerSheet 열림
- [ ] 서버 추가 → 목록에 섹션 추가, 자동 스캔 시작
- [ ] 서버 섹션 `↻` 버튼 → 해당 서버만 재스캔
- [ ] 포트 클릭 → 포워딩 시작, "포워딩 중" 섹션 최상단 표시
- [ ] 서버 이름 pill이 포워딩 행에 표시
- [ ] 포트 호버 → "브라우저에서 열기" 버튼 노출
- [ ] SSH 키 미설치 서버 → "SSH 키 인증 실패 + 복사 버튼" 표시
- [ ] `···` 메뉴 → 편집/삭제 동작
- [ ] 앱 종료 후 재실행 → 서버 목록 유지

- [ ] **Step 4: 최종 커밋**

```bash
git add -A
git commit -m "chore: delete SSHHost, SSHConfigParser, HostPickerView, PortListView"
```
