# PortBridge SSoT 정합성 리팩터 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSoT 코드 리뷰에서 식별된 4가지 위반(P1·P3·P2·P5)을 순차 제거해, `Forwarding` 도메인의 상태/메타데이터 진실 공통을 단일화한다.

**Architecture:**
- `Forwarding`은 식별 키(`serverId`)와 자신의 상태(`state`, `activatedAt`, 로컬/리모트 포트)만 보유한다.
- 서버 표시 이름은 `ServerStore`(via `AppViewModel`)가 단일 진실 공통이며, View는 렌더링 시점에 lookup한다.
- `TunnelManager`는 프로세스 수명 주기만 담당하고, `Forwarding` 객체 복제본을 보유하지 않는다.
- `StderrRingBuffer`는 NSLock 기반 `@unchecked Sendable`에서 Swift 6 strict concurrency에 안전한 `actor`로 전환한다.

**Tech Stack:** Swift 6, SwiftUI(macOS), `@Observable`, XCTest, Xcode 16, `xcodebuild`.

**Validation command (모든 Task에서 사용):**
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests \
  -quiet 2>&1 | tail -20
```

---

## Task 1: P1 — `Forwarding`/`PortConflict`에서 `serverDisplayName` 제거

서버 이름이 수정된 후에도 활성 포워딩 목록과 충돌 다이얼로그에 옛 이름이 남는 버그를 제거한다. 진실 공통은 `ServerStore`이며, View는 `AppViewModel`이 제공하는 lookup 헬퍼로 렌더링 시점에 조회한다.

**Files:**
- Modify: `PortBridge/Models/Forwarding.swift`
- Modify: `PortBridge/ViewModels/AppViewModel.swift` (lookup 헬퍼 추가, `PortConflict` 슬림화)
- Modify: `PortBridge/Views/ForwardingRowView.swift` (이름 주입으로 변경, Preview 4개)
- Modify: `PortBridge/Views/ServerListView.swift` (이름 lookup 호출 위치)
- Modify: `PortBridge/Views/ServerSectionView.swift` (`ForwardingRowView` 호출 시그니처)
- Modify: `PortBridge/ContentView.swift` (`PortConflictSheet` 및 sheet 인스턴스화)
- Modify: `PortBridge/Tunneling/TunnelManager.swift` (`Forwarding` 생성자 호출)
- Modify: `PortBridgeTests/ForwardingTests.swift` (불필요해진 테스트 교체)
- Create: `PortBridgeTests/AppViewModelDisplayNameLookupTests.swift`

---

- [ ] **Step 1.1: 회귀 테스트 작성 — 서버 이름 변경 후 lookup이 최신 이름을 반환하는지**

새 파일 `PortBridgeTests/AppViewModelDisplayNameLookupTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelDisplayNameLookupTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.AppViewModelDisplayNameLookupTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_serverDisplayName_returnsCurrentNameAfterRename() {
        let store = ServerStore(defaults: defaults)
        let original = Server(name: "prod", user: "ubuntu", host: "10.0.0.1", port: 22)
        store.add(original)
        let vm = AppViewModel(store: store)

        let renamed = Server(id: original.id, name: "production", user: "ubuntu", host: "10.0.0.1", port: 22)
        vm.updateServer(renamed)

        XCTAssertEqual(vm.serverDisplayName(for: original.id), "production")
    }

    func test_serverDisplayName_returnsNilForUnknownId() {
        let vm = AppViewModel(store: ServerStore(defaults: defaults))
        XCTAssertNil(vm.serverDisplayName(for: UUID()))
    }
}
```

> 참고: 이 테스트는 `Server`/`AppViewModel`의 현재 init 시그니처를 따라 작성됨. `Server` init에 다른 필수 인자가 있다면 `PortBridgeTests/AppViewModelServerUpdateTests.swift`에서 사용된 패턴을 그대로 차용할 것.

- [ ] **Step 1.2: 새 테스트가 컴파일 실패(헬퍼 부재)로 떨어지는지 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests/AppViewModelDisplayNameLookupTests \
  -quiet 2>&1 | tail -10
```

Expected: 컴파일 에러 `value of type 'AppViewModel' has no member 'serverDisplayName'`.

- [ ] **Step 1.3: `AppViewModel`에 lookup 헬퍼 추가**

`PortBridge/ViewModels/AppViewModel.swift`의 `// MARK: - Server CRUD` 직전(현재 line 85 위)에 삽입:

```swift
    // MARK: - Lookup

    /// View 렌더링 시점에 사용. `Forwarding`이 서버 이름을 복제하지 않고 SSoT(ServerStore)에서 조회.
    func serverDisplayName(for serverId: UUID) -> String? {
        store.servers.first { $0.id == serverId }?.displayName
    }
```

같은 파일 line 8: `private let store: ServerStore`는 그대로 유지(`private`로 둠. View는 헬퍼만 사용).

- [ ] **Step 1.4: 새 테스트가 통과하는지 빌드 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests/AppViewModelDisplayNameLookupTests \
  -quiet 2>&1 | tail -10
```

Expected: PASS (`Test Suite 'AppViewModelDisplayNameLookupTests' passed`).

- [ ] **Step 1.5: `Forwarding`에서 `serverDisplayName` 제거**

`PortBridge/Models/Forwarding.swift` 전체 교체:

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
    let serverId: UUID
    let remotePort: Int
    var localPort: Int
    var state: State

    init(
        id: UUID = UUID(),
        serverId: UUID,
        remotePort: Int,
        localPort: Int,
        state: State
    ) {
        self.id = id
        self.serverId = serverId
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
    }
}
```

- [ ] **Step 1.6: `PortConflict`에서 `serverDisplayName` 제거**

`PortBridge/ViewModels/AppViewModel.swift:227-233`(`struct PortConflict` 정의)를 다음으로 교체:

```swift
struct PortConflict: Identifiable, Equatable {
    let id = UUID()
    let serverId: UUID
    let remotePort: Int
    let attemptedLocal: Int
}
```

- [ ] **Step 1.7: `AppViewModel.startForwarding`의 `Forwarding`/`PortConflict` 생성에서 `serverDisplayName` 인자 제거**

`PortBridge/ViewModels/AppViewModel.swift`:
- line 180 `serverDisplayName: server.displayName,` 삭제
- line 206 `serverDisplayName: server.displayName,` 삭제

수정 후 `startForwarding` 내 placeholder 생성부:

```swift
        let placeholder = Forwarding(
            id: placeholderID,
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting
        )
```

충돌 catch 블록:

```swift
            pendingPortConflict = PortConflict(
                serverId: server.id,
                remotePort: remotePort,
                attemptedLocal: localPort
            )
```

- [ ] **Step 1.8: `TunnelManager.start` 내부 `Forwarding` 생성에서 인자 제거**

`PortBridge/Tunneling/TunnelManager.swift:74-80`:

```swift
        let forwarding = Forwarding(
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .active
        )
```

- [ ] **Step 1.9: `ForwardingRowView`에 표시 이름을 외부 주입으로 전환**

`PortBridge/Views/ForwardingRowView.swift` 상단 struct 선언부 수정:

```swift
struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let serverDisplayName: String?
    let onToggle: () -> Void
```

`stateLabel`의 server prefix 계산부 수정:

```swift
    private var stateLabel: String? {
        let serverPrefix = serverDisplayName.map { "\($0) · " } ?? ""
```

Preview 4개(Idle/Starting/Active/Error) 모두 `serverDisplayName:` 파라미터 추가:

```swift
#Preview("Idle · 비활성 포트") {
    ForwardingRowView(
        port: RemotePort(port: 8080, address: "0.0.0.0", processName: "nginx"),
        forwarding: nil,
        serverDisplayName: nil,
        onToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Starting") {
    ForwardingRowView(
        port: RemotePort(port: 5432, address: "127.0.0.1", processName: "postgres"),
        forwarding: Forwarding(serverId: UUID(), remotePort: 5432, localPort: 5432, state: .starting),
        serverDisplayName: "db-01",
        onToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Active") {
    ForwardingRowView(
        port: RemotePort(port: 6443, address: "0.0.0.0", processName: nil),
        forwarding: Forwarding(serverId: UUID(), remotePort: 6443, localPort: 6443, state: .active),
        serverDisplayName: "k8s-master",
        onToggle: {}
    )
    .padding()
    .frame(width: 420)
}

#Preview("Error") {
    ForwardingRowView(
        port: RemotePort(port: 3389, address: "0.0.0.0", processName: "rdp"),
        forwarding: Forwarding(serverId: UUID(), remotePort: 3389, localPort: 3389, state: .error("connection refused")),
        serverDisplayName: "win-vm",
        onToggle: {}
    )
    .padding()
    .frame(width: 420)
}
```

- [ ] **Step 1.10: `ServerListView`의 `ForwardingRowView` 호출 갱신**

`PortBridge/Views/ServerListView.swift` line 170 부근의 활성 섹션 호출:

```swift
        if let section = vm.serverSections.first(where: { $0.server.id == fw.serverId }),
           let port = portFor(forwarding: fw, section: section) {
            ForwardingRowView(
                port: port,
                forwarding: fw,
                serverDisplayName: vm.serverDisplayName(for: fw.serverId),
                onToggle: { Task { await vm.toggleForwarding(serverId: fw.serverId, for: port) } }
            )
```

`ServerSectionView`(line 57)의 호출은 비활성 행 케이스라 이름이 없음:

```swift
                ForwardingRowView(port: port, forwarding: nil, serverDisplayName: nil, onToggle: { onToggle(port) })
```

(`forwarding == nil`이면 `stateLabel`이 항상 nil이므로 `serverDisplayName: nil`이 안전.)

- [ ] **Step 1.11: `ContentView.PortConflictSheet`에 `serverDisplayName` 주입**

`PortBridge/ContentView.swift:75-85` (PortConflictSheet 선언과 init) 수정:

```swift
struct PortConflictSheet: View {
    let conflict: PortConflict
    let serverDisplayName: String?
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var localPortText: String

    init(conflict: PortConflict, serverDisplayName: String?, onConfirm: @escaping (Int) -> Void) {
        self.conflict = conflict
        self.serverDisplayName = serverDisplayName
        self.onConfirm = onConfirm
        _localPortText = State(initialValue: String(conflict.attemptedLocal + 1))
    }
```

line 91 수정:

```swift
            Text(verbatim: "다른 로컬 포트를 입력하세요. 리모트는 \(serverDisplayName ?? "서버"):\(conflict.remotePort).")
```

`ContentView`의 `.sheet(item:)` 블록 내 `PortConflictSheet` 인스턴스화(line 18-24 근방, `conflict` 클로저 인자를 받는 부분)도 갱신:

```swift
            PortConflictSheet(
                conflict: conflict,
                serverDisplayName: vm.serverDisplayName(for: conflict.serverId)
            ) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
```

- [ ] **Step 1.12: `ForwardingTests`의 `serverDisplayName` 관련 테스트 제거**

`PortBridgeTests/ForwardingTests.swift` 전체 교체:

```swift
import XCTest
@testable import PortBridge

final class ForwardingTests: XCTestCase {
    private let serverId = UUID()

    func test_idUnique() {
        let a = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        let b = Forwarding(serverId: serverId, remotePort: 80, localPort: 80, state: .idle)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_stateTransitionsRepresented() {
        let states: [Forwarding.State] = [.idle, .starting, .active, .error("oops")]
        XCTAssertEqual(states.count, 4)
    }
}
```

- [ ] **Step 1.13: 전체 테스트 빌드/실행 — 모두 통과 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests \
  -quiet 2>&1 | tail -20
```

Expected: 모든 테스트 PASS. 컴파일 에러가 남아 있다면 잔존 사용처 검색:

```bash
grep -rn "serverDisplayName" PortBridge PortBridgeTests
```

(`AppViewModel.serverDisplayName(for:)` 정의, `ForwardingRowView`/`PortConflictSheet`의 파라미터·init만 남아야 함.)

- [ ] **Step 1.14: 앱 빌드 확인**

Run:
```bash
xcodebuild build -scheme PortBridge -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 1.15: 수동 검증 — 서버 이름 변경 반영**

빌드한 앱을 실행해서:
1. 서버 1개 추가 → 포트 1개 포워딩 시작
2. 활성 섹션에서 서버 이름 옆 라벨 확인
3. 서버 편집 → 이름 변경
4. 활성 섹션 라벨이 **새 이름**으로 즉시 갱신되는지 확인

- [ ] **Step 1.16: Commit**

```bash
git add PortBridge/Models/Forwarding.swift \
        PortBridge/ViewModels/AppViewModel.swift \
        PortBridge/Views/ForwardingRowView.swift \
        PortBridge/Views/ServerListView.swift \
        PortBridge/Views/ServerSectionView.swift \
        PortBridge/ContentView.swift \
        PortBridge/Tunneling/TunnelManager.swift \
        PortBridgeTests/ForwardingTests.swift \
        PortBridgeTests/AppViewModelDisplayNameLookupTests.swift
git commit -m "refactor(ssot): drop Forwarding.serverDisplayName, lookup via ServerStore

Forwarding/PortConflict는 더 이상 서버 표시 이름을 복제하지 않는다.
View는 AppViewModel.serverDisplayName(for:)로 렌더링 시점에 ServerStore에서 조회하므로,
서버 이름을 수정해도 활성 포워딩 목록과 충돌 다이얼로그가 즉시 새 이름을 반영한다."
```

---

## Task 2: P3 — `activatedAt` Dictionary를 `Forwarding.activatedAt`으로 통합

`AppViewModel.activatedAt: [UUID: Date]`가 `forwardings`와 분리 관리되어 6곳 이상에서 동시 수정이 필요하다. `Forwarding` 구조체로 흡수해 누락 가능성을 제거한다.

**Files:**
- Modify: `PortBridge/Models/Forwarding.swift`
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Create: `PortBridgeTests/AppViewModelActivatedAtTests.swift`

---

- [ ] **Step 2.1: 회귀 테스트 작성 — `Forwarding.activatedAt` 필드**

새 파일 `PortBridgeTests/AppViewModelActivatedAtTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelActivatedAtTests: XCTestCase {

    func test_forwarding_activatedAt_defaultsToNil() {
        let fw = Forwarding(
            serverId: UUID(),
            remotePort: 80,
            localPort: 80,
            state: .idle
        )
        XCTAssertNil(fw.activatedAt)
    }

    func test_forwarding_activatedAt_canBeAssigned() {
        var fw = Forwarding(
            serverId: UUID(),
            remotePort: 80,
            localPort: 80,
            state: .active
        )
        let now = Date()
        fw.activatedAt = now
        XCTAssertEqual(fw.activatedAt, now)
    }
}
```

- [ ] **Step 2.2: 테스트 실행 — 컴파일 실패 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests/AppViewModelActivatedAtTests \
  -quiet 2>&1 | tail -10
```

Expected: 컴파일 에러 `value of type 'Forwarding' has no member 'activatedAt'`.

- [ ] **Step 2.3: `Forwarding`에 `activatedAt` 필드 추가**

`PortBridge/Models/Forwarding.swift` 전체 교체:

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
    let serverId: UUID
    let remotePort: Int
    var localPort: Int
    var state: State
    var activatedAt: Date?

    init(
        id: UUID = UUID(),
        serverId: UUID,
        remotePort: Int,
        localPort: Int,
        state: State,
        activatedAt: Date? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
        self.activatedAt = activatedAt
    }
}
```

- [ ] **Step 2.4: 새 테스트 통과 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests/AppViewModelActivatedAtTests \
  -quiet 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 2.5: `AppViewModel`에서 `activatedAt` Dictionary 선언 제거**

`PortBridge/ViewModels/AppViewModel.swift:14` 라인 **삭제**:

```swift
    private(set) var activatedAt: [UUID: Date] = [:]
```

- [ ] **Step 2.6: `activeForwardings` 정렬을 `forwarding.activatedAt` 기준으로 변경**

`AppViewModel.swift:72-83`(`activeForwardings` 전체)을 다음으로 교체:

```swift
    var activeForwardings: [Forwarding] {
        forwardings
            .filter { fw in
                switch fw.state {
                case .active, .starting, .error: return true
                case .idle: return false
                }
            }
            .sorted {
                ($0.activatedAt ?? .distantPast) > ($1.activatedAt ?? .distantPast)
            }
    }
```

- [ ] **Step 2.7: `activatedAt[…] = nil` / `removeAll()` 호출 4곳 제거**

`AppViewModel.swift`에서 다음 라인들을 **삭제**:
- line 120: `activatedAt[existing.id] = nil`
- line 139: `activatedAt[fw.id] = nil`
- line 151: `activatedAt[id] = nil`
- line 159: `activatedAt.removeAll()`

(삭제 후 각 메서드는 `tunnels.stop(...)`와 `forwardings.removeAll {...}`만 남는다.)

- [ ] **Step 2.8: `startForwarding` 단순화 — placeholder의 `activatedAt`을 결과로 이식**

`AppViewModel.swift:175-219` (`startForwarding` 전체)를 다음으로 교체:

```swift
    private func startForwarding(server: Server, remotePort: Int, localPort: Int) async {
        let placeholderID = UUID()
        let activated = Date()
        let placeholder = Forwarding(
            id: placeholderID,
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .starting,
            activatedAt: activated
        )
        forwardings.append(placeholder)

        do {
            var fw = try await tunnels.start(server: server, remotePort: remotePort, localPort: localPort)
            fw.activatedAt = activated
            if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
                forwardings[idx] = fw
            } else {
                // placeholder was removed while start() was in-flight (user cancelled)
                tunnels.stop(fw.id)
            }
        } catch PortBridgeError.forwardingDiedEarly(let stderr)
            where stderr.lowercased().contains("address already in use") {
            forwardings.removeAll { $0.id == placeholderID }
            pendingPortConflict = PortConflict(
                serverId: server.id,
                remotePort: remotePort,
                attemptedLocal: localPort
            )
        } catch let error as PortBridgeError {
            forwardings.removeAll { $0.id == placeholderID }
            showError(error.errorDescription ?? error.localizedDescription)
        } catch {
            forwardings.removeAll { $0.id == placeholderID }
            showError(error.localizedDescription)
        }
    }
```

(ID 교체로 인한 dictionary 키 이전 로직이 사라짐. placeholder의 시작 시각을 실제 tunnel `Forwarding`에 이식.)

- [ ] **Step 2.9: 전체 테스트 통과 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests \
  -quiet 2>&1 | tail -20
```

Expected: 모든 테스트 PASS.

- [ ] **Step 2.10: `activatedAt` 잔존 참조 검사**

Run:
```bash
grep -rn "activatedAt\[\|activatedAt:\s*\[UUID" PortBridge PortBridgeTests
```

Expected: 매치 없음. (`activatedAt:` 자체는 `Forwarding` init 호출에 남아 있는 게 정상.)

- [ ] **Step 2.11: 앱 빌드 확인**

```bash
xcodebuild build -scheme PortBridge -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2.12: 수동 검증 — 활성 섹션 정렬 보존**

빌드한 앱에서:
1. 서버 2개 추가, 각각 포트 포워딩 시작 (시간 차 1~2초)
2. 활성 섹션에 **늦게 시작한 것이 위**로 정렬되는지 확인
3. 위쪽 포워딩 끄고 다시 켜기 → 다시 맨 위로 올라오는지 확인

- [ ] **Step 2.13: Commit**

```bash
git add PortBridge/Models/Forwarding.swift \
        PortBridge/ViewModels/AppViewModel.swift \
        PortBridgeTests/AppViewModelActivatedAtTests.swift
git commit -m "refactor(ssot): fold activatedAt into Forwarding

분리된 [UUID: Date] dictionary는 forwardings와 6곳에서 동시 수정되어
누락 위험이 있었다. Forwarding 구조체로 흡수해 정렬과 수명 주기를
단일 컬렉션으로 일원화한다."
```

---

## Task 3: P2 — `ActiveTunnel`에서 `Forwarding` 복제본 제거

`TunnelManager.active`의 `ActiveTunnel`이 `Forwarding` 전체 객체를 보유해 살아있는 동안 `AppViewModel.forwardings`와 메모리 중복이 발생한다. `ActiveTunnel`은 `id`·`process`·`stderr`·`monitorTask`만 보유하도록 축소한다.

**Files:**
- Modify: `PortBridge/Tunneling/TunnelManager.swift`

---

> **Post-execution addendum (2026-05-21):** Task 3은 `7db0ebc`로 계획대로 4필드(`id/process/stderr/monitorTask`)에 커밋되었으나, Task 4 직후 발견된 stderr 순서/tail 손실 회귀를 수정하는 `7c9bbe2 fix(concurrency): preserve stderr order and tail via AsyncStream` 에서 `stderrContinuation`·`stderrConsumer` 2개 필드가 다시 추가되어 **최종 상태는 6필드**다. 자세한 내용은 [Task 4 Post-execution addendum](#task-4-p5--stderrringbuffer를-actor로-전환) 참고. 아래 Step 3.1/3.2는 회귀 수정 이전 시점의 계획 의도이므로, 현재 코드를 변경하지 말 것.

- [ ] **Step 3.1: `ActiveTunnel`을 슬림화**

`PortBridge/Tunneling/TunnelManager.swift:133-144`(`final class ActiveTunnel` 전체)를 다음으로 교체:

```swift
final class ActiveTunnel {
    let id: UUID
    let process: Process
    let stderr: StderrRingBuffer
    var monitorTask: Task<Void, Never>?

    init(id: UUID, process: Process, stderr: StderrRingBuffer) {
        self.id = id
        self.process = process
        self.stderr = stderr
    }
}
```

- [ ] **Step 3.2: `TunnelManager.start`에서 `ActiveTunnel` 생성 시그니처 갱신**

`PortBridge/Tunneling/TunnelManager.swift:74-91` (`let forwarding = Forwarding(...)`부터 `return forwarding`까지)을 다음으로 교체:

```swift
        let forwarding = Forwarding(
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .active
        )
        let tunnel = ActiveTunnel(id: forwarding.id, process: process, stderr: stderrBuffer)
        active[forwarding.id] = tunnel

        let id = forwarding.id
        tunnel.monitorTask = Task { [weak self] in
            await Self.waitForExit(process)
            await self?.handleTunnelExit(id: id)
        }

        return forwarding
    }
```

(반환값 `Forwarding`은 호출자에게 전달되지만, 내부 `ActiveTunnel`은 객체 복제본을 들지 않는다.)

- [ ] **Step 3.3: 전체 테스트 통과 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests \
  -quiet 2>&1 | tail -20
```

Expected: 모든 테스트 PASS.

- [ ] **Step 3.4: `ActiveTunnel.forwarding` 잔존 참조 검사**

Run:
```bash
grep -rn "tunnel\.forwarding\|ActiveTunnel(" PortBridge
```

Expected: `ActiveTunnel(id:process:stderr:)` 호출 1건, `tunnel.forwarding` 접근 0건.

- [ ] **Step 3.5: 앱 빌드 확인**

```bash
xcodebuild build -scheme PortBridge -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3.6: 수동 검증 — 포워딩 시작/중단/이상 종료**

빌드한 앱에서:
1. 포워딩 시작 → 활성으로 표시
2. 외부에서 `pkill -f "ssh -N"` 등으로 SSH 강제 종료
3. 약 2~3초 후 행이 `.error` 상태로 전환되는지 확인
4. `stopAll` 동작 정상 확인

- [ ] **Step 3.7: Commit**

```bash
git add PortBridge/Tunneling/TunnelManager.swift
git commit -m "refactor(ssot): slim ActiveTunnel to id + process resources

ActiveTunnel은 더 이상 Forwarding 객체를 복제 보유하지 않는다.
프로세스 수명 주기 추적과 stderr 버퍼만 책임지며, Forwarding 상태의
단일 진실 공통은 AppViewModel.forwardings 이다."
```

---

## Task 4: P5 — `StderrRingBuffer`를 `actor`로 전환

`@unchecked Sendable` + `NSLock` 조합은 컴파일러 검증이 없어 Swift 6 strict concurrency에서 잠재적 리스크이다. `actor`로 전환해 안전성을 컴파일 타임에 보장한다.

**Files:**
- Modify: `PortBridge/Tunneling/TunnelManager.swift`

---

> **Post-execution addendum (2026-05-21):** Task 4의 `actor` 전환은 `604e1ee`로 커밋되었으나, Step 4.2의 패턴(`Task { await stderrBuffer.append(data) }`)이 두 가지 회귀를 야기했다:
> - **순서 깨짐**: `Task` 스케줄러가 enqueue 순서와 무관하게 actor에 append를 도착시킴
> - **tail 손실**: `snapshot()` 시점에 아직 스케줄되지 않은 Task의 데이터가 누락
>
> 이를 `7c9bbe2 fix(concurrency): preserve stderr order and tail via AsyncStream`에서 다음 구조로 교체했다:
> 1. `start()`에서 `AsyncStream<Data>` 채널과 단일 consumer Task 생성 — `readabilityHandler`는 동기적으로 `continuation.yield(data)`만 호출(순서 보장)
> 2. `ActiveTunnel`은 `stderrContinuation`/`stderrConsumer`를 추가로 보유 ([Task 3 addendum](#task-3-p2--activetunnel에서-forwarding-복제본-제거) 참고)
> 3. snapshot 이전에는 `continuation.finish()` → `await consumer.value`로 모든 청크 적용 후 스냅샷
>
> 따라서 아래 Step 4.2/4.3/4.4는 회귀 수정 이전 시점의 계획 의도다. 현재 코드는 AsyncStream 파이프라인을 사용하며, 변경하지 말 것.

- [ ] **Step 4.1: `StderrRingBuffer`를 actor로 전환**

`PortBridge/Tunneling/TunnelManager.swift:146-163`을 다음으로 교체:

```swift
actor StderrRingBuffer {
    private let maxBytes = 4 * 1024
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer.removeFirst(buffer.count - maxBytes)
        }
    }

    func snapshot() -> String {
        String(data: buffer, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 4.2: `readabilityHandler`에서 `append`를 Task로 호출**

같은 파일 line 60-64(`stderrPipe.fileHandleForReading.readabilityHandler = ...`)를 다음으로 교체:

```swift
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            Task { await stderrBuffer.append(data) }
        }
```

- [ ] **Step 4.3: `start()`의 조기 종료 분기에서 `snapshot()`을 `await`로 호출**

같은 파일 line 68-72 부근을 다음으로 교체:

```swift
        try await Task.sleep(nanoseconds: 2_000_000_000)
        if !process.isRunning {
            let stderr = await stderrBuffer.snapshot()
            throw PortBridgeError.forwardingDiedEarly(stderr: stderr)
        }
```

- [ ] **Step 4.4: `handleTunnelExit`에서 `snapshot()`을 `await`로 호출**

같은 파일 line 111-116을 다음으로 교체:

```swift
    private func handleTunnelExit(id: UUID) async {
        guard let tunnel = active[id] else { return }
        let stderr = await tunnel.stderr.snapshot()
        active.removeValue(forKey: id)
        await delegate?.tunnelDidExit(id: id, stderr: stderr)
    }
```

- [ ] **Step 4.5: 전체 테스트 통과 확인**

Run:
```bash
xcodebuild test -scheme PortBridge -destination 'platform=macOS' \
  -only-testing:PortBridgeTests \
  -quiet 2>&1 | tail -20
```

Expected: 모든 테스트 PASS.

- [ ] **Step 4.6: `@unchecked Sendable` 흔적 검사**

Run:
```bash
grep -rn "@unchecked" PortBridge
```

Expected: 매치 없음.

- [ ] **Step 4.7: 앱 빌드 확인**

```bash
xcodebuild build -scheme PortBridge -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4.8: 수동 검증 — 에러 메시지 stderr 캡처**

존재하지 않는 호스트로 포워딩 시도(예: `host: no-such-host.invalid`로 서버 추가 후 임의 포트 클릭):
1. ~2초 후 에러 토스트가 떠야 함
2. 메시지에 SSH stderr 내용(예: `Could not resolve hostname`)이 포함되는지 확인 → actor가 비동기로 stderr 캡처를 정상 처리함을 의미

- [ ] **Step 4.9: Commit**

```bash
git add PortBridge/Tunneling/TunnelManager.swift
git commit -m "refactor(concurrency): convert StderrRingBuffer to actor

@unchecked Sendable + NSLock 조합을 actor로 대체해 동시성 안전성을
컴파일 타임에 보장한다. Swift 6 strict concurrency 마이그레이션에 대비."
```

---

## Self-Review 결과

**Spec coverage:**
- P1 (Forwarding/PortConflict serverDisplayName 제거) → Task 1
- P3 (activatedAt 통합) → Task 2
- P2 (ActiveTunnel 슬림화) → Task 3
- P5 (StderrRingBuffer actor화) → Task 4
- P4(ServerSectionViewModel.server)는 검증 시 위험 낮음으로 제외 — 의도된 누락

**Type consistency:**
- `Forwarding(serverId:remotePort:localPort:state:)`가 Task 1·Task 3에서 일관.
- Task 2가 추가하는 `activatedAt:`는 기본값 `nil`이라 기존 호출자(Task 3의 `TunnelManager.start`)와 호환.
- `ActiveTunnel.init(id:process:stderr:)` — Task 3 안에서 일관 (단, post-execution에서 `stderrContinuation`/`stderrConsumer` 2개 인자가 추가되어 최종 시그니처는 `init(id:process:stderr:stderrContinuation:stderrConsumer:)`. [Task 3 addendum](#task-3-p2--activetunnel에서-forwarding-복제본-제거) 참고).
- `serverDisplayName(for:) -> String?` — 모든 호출 사이트(`ForwardingRowView`, `PortConflictSheet`)에서 동일 옵셔널 시그니처.

**Placeholder scan:** 모든 단계가 실제 코드/명령/기대 출력 포함.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-21-ssot-refactor.md`. Two execution options:

**1. Subagent-Driven (recommended)** — Task 단위로 fresh subagent 디스패치, 사이에 리뷰 체크포인트.

**2. Inline Execution** — 이 세션에서 `superpowers:executing-plans`로 일괄 실행, 중간 체크포인트만.

Which approach?
