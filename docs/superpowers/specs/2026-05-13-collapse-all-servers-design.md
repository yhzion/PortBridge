# Collapse/Expand All Servers

Date: 2026-05-13

## Context

Each server section in `ServerListView` has an individual expand/collapse chevron.
Users with many servers need a way to toggle all sections at once.

## Design

### Position

A section header placed directly above the server list, mirroring the
`ActiveSectionHeader` pattern used for the "포워딩 중" section.

```
┌─ 포워딩 중 · 2 ──────── 모두 끄기 ─┐
│  ● 3000  api-server                  │
│  ● 5432  postgres                    │
├─ 모든 서버 · 3 ──────── 모두 접기 ──┤
│  ▼ [A] api-prod   192.168...  ↻ ⋯   │
│  ▼ [D] db-master  10.0.0.1   ↻ ⋯   │
│  ▶ [R] redis-node 10.0.0.5   ↻ ⋯   │
└──────────────────────────────────────┘
```

### Approach: Single Section restructuring

Server sections are wrapped in one parent `Section` with a custom header.
`ServerSectionView` drops its own `Section` wrapper and becomes plain rows.

### View changes

#### ServerSectionView

Remove `Section` wrapping. Body becomes:

```swift
var body: some View {
    sectionHeader      // rendered as a row inside the parent Section
    if section.isExpanded {
        sectionContent // same as before
    }
}
```

`sectionHeader` and `sectionContent` remain unchanged.

#### ServerListView.serverList

Wrap `ForEach(serverSections)` in a `Section` with the new header:

```swift
Section {
    ForEach(vm.serverSections) { section in
        ServerSectionView(...)
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

### New component: AllServersSectionHeader

Mirrors `ActiveSectionHeader` layout:

- Left: `"모든 서버 · \(count)"` — `.subheadline`, `.semibold`
- Right: toggle button text
  - Any section expanded → `"모두 접기"`
  - All collapsed → `"모두 펼치기"`
- Button style: `.borderless`, `.secondary`, `.caption`

### ViewModel changes

#### AppViewModel

Add two members:

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

`allExpanded` is a computed property — `@Observable` auto-tracks the
underlying `isExpanded` changes on each section.

`ServerSectionViewModel` requires no changes. The existing `toggleExpanded()`
is called conditionally.

### Files changed

| File | Change |
|---|---|
| `Views/ServerSectionView.swift` | Remove `Section` wrapper from body |
| `Views/ServerListView.swift` | Wrap ForEach in Section, add header |
| `Views/AllServersSectionHeader.swift` | New file |
| `ViewModels/AppViewModel.swift` | Add `allExpanded`, `toggleAllExpanded()` |

### Out of scope

- Keyboard shortcut for collapse/expand all
- Per-section collapse state persistence
- Search/filter interaction with collapse state
