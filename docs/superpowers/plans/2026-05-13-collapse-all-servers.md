# Collapse/Expand All Servers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "모든 서버 · N" section header with a toggle button that collapses/expands all server sections at once.

**Architecture:** Restructure `ServerSectionView` from self-contained `Section` to plain rows inside a single parent `Section` in `ServerListView`. The parent Section's header is a new `AllServersSectionHeader` component mirroring the existing `ActiveSectionHeader` pattern. ViewModel gains `allExpanded` computed property and `toggleAllExpanded()` method.

**Tech Stack:** SwiftUI, Swift Observation (`@Observable`), XCTest

---

### Task 1: Add ViewModel methods (allExpanded, toggleAllExpanded)

**Files:**
- Create: `PortBridgeTests/CollapseAllTests.swift`
- Modify: `PortBridge/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Write the failing tests**

Create `PortBridgeTests/CollapseAllTests.swift`:

```swift
import XCTest
@testable import PortBridge

@MainActor
final class CollapseAllTests: XCTestCase {

    private func makeVM(servers: [Server] = []) -> AppViewModel {
        let store = ServerStore()
        for server in servers { store.add(server) }
        return AppViewModel(store: store)
    }

    func test_allExpanded_trueWhenAllSectionsExpanded() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        XCTAssertTrue(vm.allExpanded)
    }

    func test_allExpanded_falseWhenOneCollapsed() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        vm.serverSections[0].toggleExpanded()
        XCTAssertFalse(vm.allExpanded)
    }

    func test_allExpanded_trueWhenNoSections() {
        let vm = makeVM()
        XCTAssertTrue(vm.allExpanded, "empty collection should satisfy allSatisfy")
    }

    func test_toggleAllExpanded_collapsesAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2"),
            Server(user: "u", host: "host3")
        ])
        vm.toggleAllExpanded()
        for section in vm.serverSections {
            XCTAssertFalse(section.isExpanded)
        }
        XCTAssertFalse(vm.allExpanded)
    }

    func test_toggleAllExpanded_expandsAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2")
        ])
        vm.toggleAllExpanded() // collapse all
        vm.toggleAllExpanded() // expand all
        for section in vm.serverSections {
            XCTAssertTrue(section.isExpanded)
        }
        XCTAssertTrue(vm.allExpanded)
    }

    func test_toggleAllExpanded_whenPartiallyCollapsed_expandsAll() {
        let vm = makeVM(servers: [
            Server(user: "u", host: "host1"),
            Server(user: "u", host: "host2"),
            Server(user: "u", host: "host3")
        ])
        vm.serverSections[1].toggleExpanded() // collapse only #2
        XCTAssertFalse(vm.allExpanded)

        vm.toggleAllExpanded() // should expand all (since not all expanded)
        XCTAssertTrue(vm.allExpanded)
        for section in vm.serverSections {
            XCTAssertTrue(section.isExpanded)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/CollapseAllTests 2>&1 | tail -20`
Expected: Compile error — `AppViewModel` has no member `allExpanded` or `toggleAllExpanded()`

- [ ] **Step 3: Write minimal implementation**

Add to `PortBridge/ViewModels/AppViewModel.swift`, after the `matches(_:)` method (around line 26):

```swift
    var allExpanded: Bool {
        serverSections.allSatisfy(\.isExpanded)
    }

    func toggleAllExpanded() {
        let shouldExpand = !allExpanded
        for section in serverSections {
            if section.isExpanded != shouldExpand {
                section.toggleExpanded()
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' -only-testing:PortBridgeTests/CollapseAllTests 2>&1 | tail -20`
Expected: 6/6 tests PASS

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add PortBridge/ViewModels/AppViewModel.swift PortBridgeTests/CollapseAllTests.swift
git commit -m "feat: add allExpanded & toggleAllExpanded to AppViewModel"
```

---

### Task 2: Create AllServersSectionHeader component

**Files:**
- Create: `PortBridge/Views/AllServersSectionHeader.swift`

- [ ] **Step 1: Create the component**

Create `PortBridge/Views/AllServersSectionHeader.swift`:

```swift
import SwiftUI

struct AllServersSectionHeader: View {
    let count: Int
    let allExpanded: Bool
    let onToggleAll: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: "모든 서버 · \(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
            Button(allExpanded ? "모두 접기" : "모두 펼치기", action: onToggleAll)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PortBridge/Views/AllServersSectionHeader.swift
git commit -m "feat: add AllServersSectionHeader component"
```

---

### Task 3: Restructure ServerSectionView — remove Section wrapper

**Files:**
- Modify: `PortBridge/Views/ServerSectionView.swift:26-34`

- [ ] **Step 1: Remove Section wrapper from body**

Replace the current `body` property (lines 26-34):

```swift
    var body: some View {
        Section {
            if section.isExpanded {
                sectionContent
            }
        } header: {
            sectionHeader
        }
    }
```

With:

```swift
    var body: some View {
        sectionHeader
        if section.isExpanded {
            sectionContent
        }
    }
```

This removes the `Section` wrapper. `sectionHeader` and `sectionContent` now render as plain rows inside the parent `Section` that `ServerListView` will provide.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED (may show warnings about unused Section imports — none expected)

- [ ] **Step 3: Commit**

```bash
git add PortBridge/Views/ServerSectionView.swift
git commit -m "refactor: remove Section wrapper from ServerSectionView"
```

---

### Task 4: Update ServerListView — wrap in Section with AllServersSectionHeader

**Files:**
- Modify: `PortBridge/Views/ServerListView.swift:76-88`

- [ ] **Step 1: Wrap ForEach in Section with header**

Replace the server sections block in `serverList` (lines 77-88):

```swift
            // 서버별 섹션
            ForEach(vm.serverSections) { section in
                ServerSectionView(
                    section: section,
                    activeForwardings: vm.activeForwardings,
                    matches: { vm.matches($0) },
                    onToggle: { port in
                        Task { await vm.toggleForwarding(serverId: section.server.id, for: port) }
                    },
                    onEdit: { editingServer = section.server },
                    onDelete: { vm.deleteServer(section.server) }
                )
            }
```

With:

```swift
            // 서버별 섹션
            Section {
                ForEach(vm.serverSections) { section in
                    ServerSectionView(
                        section: section,
                        activeForwardings: vm.activeForwardings,
                        matches: { vm.matches($0) },
                        onToggle: { port in
                            Task { await vm.toggleForwarding(serverId: section.server.id, for: port) }
                        },
                        onEdit: { editingServer = section.server },
                        onDelete: { vm.deleteServer(section.server) }
                    )
                }
            } header: {
                AllServersSectionHeader(
                    count: vm.serverSections.count,
                    allExpanded: vm.allExpanded,
                    onToggleAll: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            vm.toggleAllExpanded()
                        }
                    }
                )
            }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -project PortBridge.xcodeproj -scheme PortBridge -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add PortBridge/Views/ServerListView.swift
git commit -m "feat: wrap server sections in parent Section with collapse/expand all header"
```

---

### Task 5: Manual verification

- [ ] **Step 1: Launch the app**

Run the app from Xcode or: `open PortBridge.xcodeproj`

- [ ] **Step 2: Verify the following behaviors**

1. With 0 servers: "모든 서버 · 0" header not visible (empty list shows "등록된 서버가 없습니다")
2. With 1+ servers: "모든 서버 · N" header appears above server sections
3. Click "모두 접기" → all server sections collapse, button text changes to "모두 펼치기"
4. Click "모두 펼치기" → all server sections expand, button text changes to "모두 접기"
5. Collapse one section manually → button text changes to "모두 펼치기"
6. Click "모두 펼치기" → all sections expand including the manually collapsed one
7. Spring animation plays smoothly on toggle
8. Individual section chevrons still work independently
9. "포워딩 중" section and "모두 끄기" unaffected
10. Search bar, add server, refresh all unaffected
