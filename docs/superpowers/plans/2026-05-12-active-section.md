# Active 포트 섹션 분리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PortBridge의 `PortListView`에서 활성화된 포트(`.starting / .active / .error`)를 상단 별도 섹션으로 분리하고, 토글 시 row가 섹션 간 우아하게 reorder 되도록 한다.

**Architecture:** `AppViewModel`에 `activatedAt: [UUID: Date]` 사전과 derived 컬렉션 2개(`activeForwardedPorts`, `inactivePorts`)를 추가하고, `PortListView`를 단일 `List`에서 두 개의 `Section`으로 재구성한다. `.animation(.spring, value: activeIds)`로 reorder 애니메이션을 얻고 native macOS List 동작을 유지한다.

**Tech Stack:** SwiftUI (macOS), Observation framework (`@Observable`), XCTest, async/await.

**Spec:** `docs/superpowers/specs/2026-05-12-active-section-design.md`

---

## File Structure

신규 파일:
- `PortBridge/Views/ActiveSectionHeader.swift` — 헤더 컴포넌트 (카운트 + "모두 끄기")
- `PortBridge/Views/AllPortsSectionHeader.swift` — 헤더 컴포넌트 (전체 카운트)
- `PortBridgeTests/AppViewModelActiveSectionTests.swift` — 신규 단위테스트

수정 파일:
- `PortBridge/ViewModels/AppViewModel.swift` — `activatedAt`, derived 2개, `stopAllForCurrentHost()`, `toggleForwarding`/`startForwarding` 보강
- `PortBridge/Views/ForwardingRowView.swift` — `isActive: Bool` prop + 시각적 강조
- `PortBridge/Views/PortListView.swift` — 두 Section 구조 + 애니메이션, 기존 카운트 라인 제거

데이터 모델(`Forwarding`, `RemotePort`, `SSHHost`)은 변경 없음.

---

## Task 1: `activatedAt` 사전과 derived 컬렉션 추가 (순수 로직 + TDD)

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Create: `PortBridgeTests/AppViewModelActiveSectionTests.swift`

이 task는 `AppViewModel`이 가진 순수 데이터 변환 로직만 다룬다. `tunnels`/`scanner` 호출 없음 — `forwardings` 배열을 직접 set하여 테스트한다.

- [ ] **Step 1: 신규 테스트 파일을 만들고 첫 실패 테스트 작성**

`PortBridgeTests/AppViewModelActiveSectionTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class AppViewModelActiveSectionTests: XCTestCase {
    private func makeVM() -> AppViewModel {
        let vm = AppViewModel(parser: { [] })
        vm.selectedHost = SSHHost(name: "prod")
        return vm
    }

    private func remotePort(_ port: Int) -> RemotePort {
        RemotePort(port: port, address: "0.0.0.0", processName: "p\(port)")
    }

    func test_activeForwardedPorts_includesStartingActiveAndError() {
        let vm = makeVM()
        vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
        vm.forwardings = [
            Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .starting),
            Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active),
            Forwarding(host: "prod", remotePort: 22, localPort: 22, state: .error("nope"))
        ]
        let active = vm.activeForwardedPorts
        XCTAssertEqual(Set(active.map { $0.port.port }), [8080, 5432, 22])
    }
}
```

- [ ] **Step 2: 테스트 실행 → 컴파일 실패 확인**

Run (Xcode 또는):
```
xcodebuild test -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/AppViewModelActiveSectionTests/test_activeForwardedPorts_includesStartingActiveAndError
```
Expected: `'activeForwardedPorts'` 미정의로 컴파일 실패.

- [ ] **Step 3: `AppViewModel`에 `activeForwardedPorts` derived 추가 (최소 구현)**

`PortBridge/ViewModels/AppViewModel.swift` 의 `var filteredPorts: [RemotePort] { ... }` 바로 아래에 삽입:

```swift
var activeForwardedPorts: [(port: RemotePort, forwarding: Forwarding)] {
    let active = forwardings.filter { fw in
        guard fw.host == selectedHost?.name else { return false }
        switch fw.state {
        case .active, .starting, .error: return true
        case .idle: return false
        }
    }
    return active.compactMap { fw in
        ports.first(where: { $0.port == fw.remotePort }).map { (port: $0, forwarding: fw) }
    }
}
```

- [ ] **Step 4: 테스트 실행 → PASS 확인**

Run: 동일 명령
Expected: PASS.

- [ ] **Step 5: 정렬 동작 테스트 추가**

테스트 파일에 추가:

```swift
func test_activeForwardedPorts_sortsByActivatedAtDesc() {
    let vm = makeVM()
    vm.ports = [remotePort(8080), remotePort(5432)]
    let firstID = UUID()
    let secondID = UUID()
    vm.forwardings = [
        Forwarding(id: firstID, host: "prod", remotePort: 8080, localPort: 8080, state: .active),
        Forwarding(id: secondID, host: "prod", remotePort: 5432, localPort: 5432, state: .active)
    ]
    vm.setActivatedAtForTesting(firstID, Date(timeIntervalSince1970: 100))
    vm.setActivatedAtForTesting(secondID, Date(timeIntervalSince1970: 200))

    let active = vm.activeForwardedPorts
    XCTAssertEqual(active.map { $0.port.port }, [5432, 8080], "최근 활성화가 위")
}
```

- [ ] **Step 6: 테스트 실행 → 컴파일 실패 (정렬 미구현 + setActivatedAtForTesting 미정의)**

Expected: `'setActivatedAtForTesting'` 미정의 + 정렬 안 됨.

- [ ] **Step 7: `activatedAt` 사전과 정렬 로직 추가**

`AppViewModel.swift` 상태 변수 영역에 추가 (`var pendingPortConflict: PortConflict?` 아래):

```swift
private(set) var activatedAt: [UUID: Date] = [:]

#if DEBUG
func setActivatedAtForTesting(_ id: UUID, _ date: Date) {
    activatedAt[id] = date
}
#endif
```

`activeForwardedPorts`를 정렬 포함하도록 교체:

```swift
var activeForwardedPorts: [(port: RemotePort, forwarding: Forwarding)] {
    let active = forwardings.filter { fw in
        guard fw.host == selectedHost?.name else { return false }
        switch fw.state {
        case .active, .starting, .error: return true
        case .idle: return false
        }
    }
    return active
        .compactMap { fw in
            ports.first(where: { $0.port == fw.remotePort }).map { (port: $0, forwarding: fw) }
        }
        .sorted {
            activatedAt[$0.forwarding.id, default: .distantPast]
            > activatedAt[$1.forwarding.id, default: .distantPast]
        }
}
```

- [ ] **Step 8: 두 테스트 실행 → PASS**

Run:
```
xcodebuild test -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/AppViewModelActiveSectionTests
```
Expected: 2 tests pass.

- [ ] **Step 9: `inactivePorts` 테스트 추가**

```swift
func test_inactivePorts_excludesActivePortNumbers() {
    let vm = makeVM()
    vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
    vm.forwardings = [
        Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active)
    ]
    let inactive = vm.inactivePorts
    XCTAssertEqual(Set(inactive.map { $0.port }), [5432, 22])
}

func test_inactivePorts_appliesSearchFilter() {
    let vm = makeVM()
    vm.ports = [remotePort(8080), remotePort(5432), remotePort(22)]
    vm.forwardings = []
    vm.searchText = "80"
    let inactive = vm.inactivePorts
    XCTAssertEqual(inactive.map { $0.port }, [8080])
}

func test_activeForwardedPorts_ignoresSearchFilter() {
    let vm = makeVM()
    vm.ports = [remotePort(8080), remotePort(5432)]
    vm.forwardings = [
        Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active)
    ]
    vm.searchText = "999"
    XCTAssertEqual(vm.activeForwardedPorts.map { $0.port.port }, [5432])
}
```

- [ ] **Step 10: 컴파일 실패 확인 → `inactivePorts` 미정의**

- [ ] **Step 11: `inactivePorts` derived 추가**

`activeForwardedPorts` 바로 아래:

```swift
var inactivePorts: [RemotePort] {
    let activePortNums = Set(activeForwardedPorts.map { $0.port.port })
    return filteredPorts.filter { !activePortNums.contains($0.port) }
}
```

- [ ] **Step 12: 모든 테스트 PASS 확인**

Run: 동일 명령
Expected: 5 tests pass (3 신규 + 2 기존).

- [ ] **Step 13: 호스트 전환 시 active가 비는지 테스트 + PASS 확인**

```swift
func test_activeForwardedPorts_emptyWhenHostMismatches() {
    let vm = makeVM()
    vm.selectedHost = SSHHost(name: "other")
    vm.ports = [remotePort(8080)]
    vm.forwardings = [
        Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active)
    ]
    XCTAssertTrue(vm.activeForwardedPorts.isEmpty)
}
```

기존 구현이 `fw.host == selectedHost?.name` 가드를 가지므로 PASS여야 함.

- [ ] **Step 14: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelActiveSectionTests.swift
git commit -m "feat(viewmodel): activatedAt + activeForwardedPorts/inactivePorts derived"
```

---

## Task 2: `stopAllForCurrentHost()` 메서드 추가

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`
- Modify: `PortBridgeTests/AppViewModelActiveSectionTests.swift`

이 task는 `tunnels.stop()` side effect를 직접 검증하지 않는다 (TunnelManager는 protocol 추출이 안 되어 있어 Mock이 어려움 — 추후 task). 대신 **`forwardings` 배열과 `activatedAt` 사전이 올바르게 정리되는지**를 검증한다.

- [ ] **Step 1: 실패 테스트 작성**

`AppViewModelActiveSectionTests.swift` 에 추가:

```swift
func test_stopAllForCurrentHost_clearsOnlyCurrentHostForwardings() {
    let vm = makeVM()  // selectedHost = "prod"
    vm.forwardings = [
        Forwarding(host: "prod", remotePort: 8080, localPort: 8080, state: .active),
        Forwarding(host: "prod", remotePort: 5432, localPort: 5432, state: .active),
        Forwarding(host: "other", remotePort: 22, localPort: 22, state: .active)
    ]
    vm.stopAllForCurrentHost()
    XCTAssertEqual(vm.forwardings.count, 1)
    XCTAssertEqual(vm.forwardings.first?.host, "other")
}

func test_stopAllForCurrentHost_clearsActivatedAtForRemovedIDs() {
    let vm = makeVM()
    let id1 = UUID()
    let id2 = UUID()
    vm.forwardings = [
        Forwarding(id: id1, host: "prod", remotePort: 8080, localPort: 8080, state: .active),
        Forwarding(id: id2, host: "other", remotePort: 22, localPort: 22, state: .active)
    ]
    vm.setActivatedAtForTesting(id1, Date())
    vm.setActivatedAtForTesting(id2, Date())

    vm.stopAllForCurrentHost()
    XCTAssertNil(vm.activatedAt[id1])
    XCTAssertNotNil(vm.activatedAt[id2])
}
```

- [ ] **Step 2: 컴파일 실패 확인 → `stopAllForCurrentHost` 미정의**

Run:
```
xcodebuild test -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/AppViewModelActiveSectionTests/test_stopAllForCurrentHost_clearsOnlyCurrentHostForwardings
```

- [ ] **Step 3: `stopAllForCurrentHost()` 구현**

`AppViewModel.swift` 의 `shutdownAll()` 위에 추가:

```swift
func stopAllForCurrentHost() {
    guard let host = selectedHost else { return }
    let mine = forwardings.filter { $0.host == host.name }
    for fw in mine {
        tunnels.stop(fw.id)
        activatedAt[fw.id] = nil
    }
    forwardings.removeAll { $0.host == host.name }
}
```

- [ ] **Step 4: 테스트 PASS 확인**

Expected: 2 tests pass.

> **참고**: `tunnels.stop(fw.id)`는 실제 TunnelManager 인스턴스에 대해 호출되지만 `active[id]`에 매칭이 없으면 no-op (early return). 테스트에서는 실제 ssh process가 없어도 안전.

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelActiveSectionTests.swift
git commit -m "feat(viewmodel): stopAllForCurrentHost"
```

---

## Task 3: `startForwarding` / `toggleForwarding`에서 `activatedAt` 관리

**Files:**
- Modify: `PortBridge/ViewModels/AppViewModel.swift`

이 변경은 라이프사이클 관련이라 비동기 흐름이 끼어 통합테스트가 까다롭다. **간접적으로 검증 가능한 부분**(toggle off에서 사전 정리)만 단위테스트하고, 나머지(start 성공 시 id 전이)는 spec §5.1을 그대로 구현 후 수동 QA에서 검증한다.

- [ ] **Step 1: toggle off 시 사전 정리 테스트 작성**

`AppViewModelActiveSectionTests.swift` 에 추가:

```swift
func test_toggleForwardingOff_removesActivatedAtEntry() async {
    let vm = makeVM()
    let port = remotePort(8080)
    let fwID = UUID()
    vm.ports = [port]
    vm.forwardings = [
        Forwarding(id: fwID, host: "prod", remotePort: 8080, localPort: 8080, state: .active)
    ]
    vm.setActivatedAtForTesting(fwID, Date())

    await vm.toggleForwarding(for: port)

    XCTAssertNil(vm.activatedAt[fwID])
    XCTAssertTrue(vm.forwardings.isEmpty)
}
```

- [ ] **Step 2: 테스트 실행 → 현재는 `activatedAt`이 비어있으니 nil 단언은 통과하지만 forwardings는 비어야 PASS**

Run: 해당 테스트만.
Expected: PASS (현재 toggleForwarding off 분기가 `forwardings.removeAll`은 하지만 activatedAt은 안 비움 — assert가 nil이라 통과처럼 보일 수 있음). **따라서 토글 전에 명시적으로 activatedAt에 값을 넣었는데 토글 후에도 남아있는지를 검증해야 함.** 위 테스트가 그렇게 작성됨 → 토글 off 후 nil 단언 → 현재 코드는 사전 정리 안 하므로 FAIL.

- [ ] **Step 3: `toggleForwarding`의 off 분기에 `activatedAt` 정리 추가**

`AppViewModel.swift` 의 `toggleForwarding` 함수에서:

```swift
func toggleForwarding(for port: RemotePort) async {
    guard let host = selectedHost else { return }
    if let existing = forwardings.first(where: { $0.host == host.name && $0.remotePort == port.port }) {
        tunnels.stop(existing.id)
        activatedAt[existing.id] = nil          // ← 신규
        forwardings.removeAll { $0.id == existing.id }
        return
    }
    await startForwarding(host: host.name, remotePort: port.port, localPort: port.port)
}
```

- [ ] **Step 4: 테스트 PASS 확인**

- [ ] **Step 5: `startForwarding`의 placeholder 시점에 `activatedAt` 기록 + id 전이 추가**

`AppViewModel.swift` 의 `private func startForwarding` 전체를 다음으로 교체:

```swift
private func startForwarding(host: String, remotePort: Int, localPort: Int) async {
    let placeholderID = UUID()
    let placeholder = Forwarding(
        id: placeholderID,
        host: host,
        remotePort: remotePort,
        localPort: localPort,
        state: .starting
    )
    forwardings.append(placeholder)
    activatedAt[placeholderID] = Date()                    // ← 신규

    do {
        let fw = try await tunnels.start(host: host, remotePort: remotePort, localPort: localPort)
        if let idx = forwardings.firstIndex(where: { $0.id == placeholderID }) {
            forwardings[idx] = fw
        } else {
            forwardings.append(fw)
        }
        // id 전이: placeholder의 활성화 시각을 새 fw.id로 이전
        if let ts = activatedAt.removeValue(forKey: placeholderID) {
            activatedAt[fw.id] = ts
        }
    } catch PortBridgeError.forwardingDiedEarly(let stderr) where stderr.lowercased().contains("address already in use") {
        forwardings.removeAll { $0.id == placeholderID }
        activatedAt[placeholderID] = nil                    // ← 신규
        pendingPortConflict = PortConflict(host: host, remotePort: remotePort, attemptedLocal: localPort)
    } catch let error as PortBridgeError {
        forwardings.removeAll { $0.id == placeholderID }
        activatedAt[placeholderID] = nil                    // ← 신규
        lastError = error.errorDescription
    } catch {
        forwardings.removeAll { $0.id == placeholderID }
        activatedAt[placeholderID] = nil                    // ← 신규
        lastError = error.localizedDescription
    }
}
```

- [ ] **Step 6: 컴파일/모든 기존 테스트가 여전히 통과하는지 확인**

Run:
```
xcodebuild test -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests
```
Expected: 모든 기존 + 신규 테스트 PASS.

- [ ] **Step 7: 커밋**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/AppViewModelActiveSectionTests.swift
git commit -m "feat(viewmodel): manage activatedAt across forwarding lifecycle"
```

---

## Task 4: `ForwardingRowView`에 `isActive` 시각적 강조 추가

**Files:**
- Modify: `PortBridge/Views/ForwardingRowView.swift`

UI 변경. 단위테스트보다는 수동 QA. 컴파일 + 호출부 일치만 검증.

- [ ] **Step 1: `ForwardingRowView`에 `isActive: Bool` prop 추가**

`PortBridge/Views/ForwardingRowView.swift` 의 struct 본문 상단을 수정:

```swift
struct ForwardingRowView: View {
    let port: RemotePort
    let forwarding: Forwarding?
    let isActive: Bool                  // ← 신규
    let onToggle: () -> Void
    // ... (이하 기존 그대로)
```

- [ ] **Step 2: body 끝부분에 배경 + 좌측 accent bar 추가**

기존 body의 최외곽 HStack에 chain된 `.padding`, `.contentShape`, `.onTapGesture`, `.help` 라인은 그대로 유지. 그 직전에 `.background`와 `.overlay`를 추가:

```swift
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // ... 기존 그대로 ...
        }
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isStarting else { return }
            onToggle()
        }
        .help(forwarding?.state == .active ? "클릭해 포워딩 끄기" : "클릭해 포워딩 켜기")
    }
```

- [ ] **Step 3: 빌드 확인 → 호출부가 깨졌을 것**

Run:
```
xcodebuild build -scheme PortBridge -destination 'platform=macOS'
```
Expected: `PortListView.swift` 에서 `ForwardingRowView(...)` 호출 시 `isActive` 미지정 컴파일 에러.

- [ ] **Step 4: 임시로 `PortListView`의 기존 호출에 `isActive: false` 추가하여 빌드 복구**

`PortBridge/Views/PortListView.swift` 의 `ForwardingRowView(port:forwarding:onToggle:)` 호출에 `isActive: false`를 끼워 넣는다:

```swift
List(vm.filteredPorts) { port in
    ForwardingRowView(
        port: port,
        forwarding: vm.forwardings.first {
            $0.remotePort == port.port && $0.host == vm.selectedHost?.name
        },
        isActive: false,
        onToggle: { Task { await vm.toggleForwarding(for: port) } }
    )
}
```

(다음 task에서 이 List 전체가 두 Section으로 교체되므로 임시 조치)

- [ ] **Step 5: 빌드 PASS 확인**

Run: 동일 build 명령
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: 커밋**

```bash
git add PortBridge/Views/ForwardingRowView.swift PortBridge/Views/PortListView.swift
git commit -m "feat(views): isActive prop on ForwardingRowView (tint + accent bar)"
```

---

## Task 5: `ActiveSectionHeader`와 `AllPortsSectionHeader` 신규 컴포넌트

**Files:**
- Create: `PortBridge/Views/ActiveSectionHeader.swift`
- Create: `PortBridge/Views/AllPortsSectionHeader.swift`

- [ ] **Step 1: `ActiveSectionHeader.swift` 작성**

`PortBridge/Views/ActiveSectionHeader.swift`:

```swift
import SwiftUI

struct ActiveSectionHeader: View {
    let count: Int
    let onStopAll: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: "포워딩 중 · \(count)")
            Spacer()
            Button("모두 끄기", action: onStopAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
```

- [ ] **Step 2: `AllPortsSectionHeader.swift` 작성**

`PortBridge/Views/AllPortsSectionHeader.swift`:

```swift
import SwiftUI

struct AllPortsSectionHeader: View {
    let count: Int

    var body: some View {
        Text(verbatim: "전체 포트 · \(count)")
    }
}
```

- [ ] **Step 3: 빌드 확인**

Run:
```
xcodebuild build -scheme PortBridge -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED.

> **참고**: 새 파일은 Xcode 프로젝트의 build phase에 포함되어야 한다. `xcodebuild` CLI가 path 기반 컴파일을 인식하지 않으면 `PortBridge.xcodeproj` 의 file refs에 추가해야 함. 만약 빌드 실패 시 Xcode UI 또는 [xcodeproj gem]을 통해 file ref를 추가하라.

- [ ] **Step 4: 커밋**

```bash
git add PortBridge/Views/ActiveSectionHeader.swift PortBridge/Views/AllPortsSectionHeader.swift PortBridge.xcodeproj
git commit -m "feat(views): ActiveSectionHeader + AllPortsSectionHeader"
```

---

## Task 6: `PortListView`를 두 Section + 애니메이션으로 재구성

**Files:**
- Modify: `PortBridge/Views/PortListView.swift`

- [ ] **Step 1: `PortListView`의 `List` 블록을 두 Section 구조로 교체**

`PortBridge/Views/PortListView.swift` 전체를 다음으로 교체:

```swift
import SwiftUI

struct PortListView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.ports.isEmpty {
                ContentUnavailableView(
                    vm.selectedHost == nil ? "서버를 선택해주세요" : "열려있는 포트가 없습니다",
                    systemImage: vm.selectedHost == nil ? "server.rack" : "magnifyingglass",
                    description: Text(vm.selectedHost == nil
                        ? "위에서 SSH 서버를 선택하고 '포트 검색'을 눌러보세요."
                        : "이 서버에서 1000~65535 범위에 리스닝 중인 포트가 없습니다.")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("포트 번호나 프로세스 이름으로 찾기", text: $vm.searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                List {
                    if !vm.activeForwardedPorts.isEmpty {
                        Section {
                            ForEach(vm.activeForwardedPorts, id: \.port.id) { entry in
                                ForwardingRowView(
                                    port: entry.port,
                                    forwarding: entry.forwarding,
                                    isActive: true,
                                    onToggle: { Task { await vm.toggleForwarding(for: entry.port) } }
                                )
                            }
                        } header: {
                            ActiveSectionHeader(
                                count: vm.activeForwardedPorts.count,
                                onStopAll: { vm.stopAllForCurrentHost() }
                            )
                        }
                    }

                    Section {
                        ForEach(vm.inactivePorts) { port in
                            ForwardingRowView(
                                port: port,
                                forwarding: nil,
                                isActive: false,
                                onToggle: { Task { await vm.toggleForwarding(for: port) } }
                            )
                        }
                    } header: {
                        AllPortsSectionHeader(count: vm.inactivePorts.count)
                    }
                }
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.85),
                    value: vm.activeForwardedPorts.map(\.port.id)
                )
            }
        }
    }
}
```

기존 "검색된 포트 N개 / 총 M개" HStack은 제거됨 (섹션 헤더가 카운트를 전달).

- [ ] **Step 2: 빌드 확인**

Run:
```
xcodebuild build -scheme PortBridge -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: 전체 테스트 실행 — 모든 기존+신규 단위테스트 PASS**

Run:
```
xcodebuild test -scheme PortBridge -destination 'platform=macOS'
```
Expected: 모두 PASS.

- [ ] **Step 4: 수동 QA — 앱 실행 후 시나리오 검증**

Run: Xcode에서 Run (`⌘R`).

체크리스트:
1. SSH 호스트 선택 → 포트 스캔 → inactive row 1개 클릭 → row가 위로 슬라이드하며 "포워딩 중 · 1" 섹션 생성
2. 추가로 2개 토글 → 최근 켠 것이 위에 쌓이는지
3. 검색어 "80" 입력 → 활성 섹션은 그대로, 비활성 섹션만 필터
4. "모두 끄기" 클릭 → 활성 row 모두가 비활성 섹션으로 이동, 활성 섹션 사라짐
5. 활성 row의 좌측 accent bar와 옅은 tint가 라이트/다크 모드 모두에서 가독성 OK
6. error 상태 (잘못된 포트 등) → 빨간 점으로 활성 섹션에 잔류, 클릭 시 재시도
7. 호스트 전환 → 활성 섹션이 사라지고 새 호스트의 포트만 표시

- [ ] **Step 5: 커밋**

```bash
git add PortBridge/Views/PortListView.swift
git commit -m "feat(views): split PortListView into active/inactive sections with spring reorder"
```

---

## Self-Review

이 plan을 spec(`docs/superpowers/specs/2026-05-12-active-section-design.md`)에 대해 검증한 결과:

**Spec coverage:**
- §3.1 컨테이너 결정: Task 6에서 `List` + `Section` 구현 ✓
- §3.2 활성 상태 범위: Task 1 Step 3의 switch에 `.active/.starting/.error` ✓
- §3.3 정렬: Task 1 Step 7 ✓
- §3.4 검색 영향: Task 1 Step 9의 `test_activeForwardedPorts_ignoresSearchFilter` + `inactivePorts`가 `filteredPorts` 사용 ✓
- §3.5 confirmation 없는 모두 끄기: Task 2 + Task 5 헤더 버튼이 즉시 호출 ✓
- §5.1 `activatedAt` 관리: Task 3에서 placeholder 기록·id 전이·실패 정리 모두 구현 ✓
- §5.3 `isActive` 시각: Task 4 ✓
- §5.4-5.5 헤더 컴포넌트: Task 5 ✓
- §8 테스트 전략: Task 1·2·3의 단위테스트 + Task 6 수동 QA ✓

**Placeholder/TODO scan:** 없음.

**Type consistency:** 
- `activeForwardedPorts: [(port: RemotePort, forwarding: Forwarding)]` Task 1·2·3·6에서 동일 시그니처.
- `stopAllForCurrentHost()` 시그니처 Task 2·6 동일.
- `setActivatedAtForTesting` DEBUG 전용 — 프로덕션 코드에서는 미참조.

문제 없음.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-12-active-section.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.
