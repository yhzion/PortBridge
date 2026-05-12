# Manual Server Registration — Design Spec

**Date:** 2026-05-12  
**Status:** Approved

---

## Overview

SSH 서버를 `~/.ssh/config`에서 자동으로 읽어오는 방식을 폐기하고, 사용자가 직접 서버를 등록·관리하는 방식으로 전환한다. 등록한 서버 목록은 앱 안에 저장되며, 멀티 서버 포트 현황을 단일 리스트(서버별 섹션)로 표시한다.

---

## 삭제 대상

- `SSHHost` 모델
- `SSHConfigParser`
- `HostPickerView` (드롭다운 서버 선택 UI)
- `AppViewModel`의 `hosts`, `selectedHost`, `ports`, `isScanning` 프로퍼티

---

## 데이터 모델

### `Server`

```swift
struct Server: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String?      // nil이면 host로만 표시
    var user: String
    var host: String       // IP 또는 hostname
    var port: Int          // 기본 22

    var displayName: String {
        name.map { "\($0) (\(host))" } ?? host
    }

    var sshTarget: String { "\(user)@\(host)" }
}
```

### `ServerScanState`

```swift
enum ServerScanState: Equatable {
    case idle
    case scanning
    case loaded([RemotePort])
    case error(String)
    case authFailed(copyCommand: String)  // e.g. "ssh-copy-id user@host"
}
```

### `Forwarding` 변경

`host: String` → `serverId: UUID` + `serverDisplayName: String`으로 교체.  
포워딩 행에서 서버 이름을 별도 API 없이 바로 표시하기 위해 `serverDisplayName`을 비정규화하여 저장한다.

---

## 영속성

### `ServerStore`

```swift
@Observable final class ServerStore {
    private(set) var servers: [Server]

    func add(_ server: Server)
    func update(_ server: Server)
    func delete(_ server: Server)

    // UserDefaults 키: "portbridge.servers"
    // Codable JSON으로 직렬화
}
```

비밀번호는 저장하지 않는다. 인증은 SSH 키 기반만 지원 (`BatchMode=yes` 유지).

### `TunnelManager` 인터페이스 변경

현재 `start(host: String, ...)` 는 SSH config alias를 그대로 넘김. 수동 서버는 `user@IP`와 `-p port` 플래그가 필요하므로 시그니처 변경:

```swift
// 변경 전
func start(host: String, remotePort: Int, localPort: Int) async throws -> Forwarding

// 변경 후
func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding
// 내부적으로: ssh -N -p server.port ... server.sshTarget
```

---

## 아키텍처

### 컴포넌트 책임

| 컴포넌트 | 책임 |
|---|---|
| `ServerStore` | 서버 목록 UserDefaults 영속화 |
| `ServerSectionViewModel` | 서버 1개의 스캔 상태, 포트 목록 독립 관리 |
| `AppViewModel` | serverSections 생성·관리, 포워딩 전체 관리, TunnelManager 위임 |
| `TunnelManager` | SSH 프로세스 생명주기 (`start` 시그니처 소폭 변경) |

### 데이터 흐름

```
ServerStore (UserDefaults)
    ↓ servers 변경 시
AppViewModel
    ↓ 각 Server마다
ServerSectionViewModel[]   ←→   PortScanner (스캔)
    ↓ forwardings
TunnelManager (SSH -L)
```

### `ServerSectionViewModel`

```swift
@Observable final class ServerSectionViewModel: Identifiable {
    let server: Server
    private(set) var scanState: ServerScanState = .idle
    private(set) var isExpanded: Bool = true

    func scan() async
    // - PortScanner 호출
    // - stderr에 "Permission denied (publickey)" 포함 시 → .authFailed
    // - 그 외 에러 → .error
    // - 성공 → .loaded([RemotePort])

    func toggleExpanded()
}
```

### `AppViewModel` (축소)

```swift
@Observable final class AppViewModel {
    var serverSections: [ServerSectionViewModel]
    var forwardings: [Forwarding]
    private(set) var activatedAt: [UUID: Date] = [:]

    func scanAll() async          // 전체 서버 lazy 스캔
    func toggleForwarding(serverId: UUID, port: RemotePort) async
    func stopAll(for serverId: UUID)
    func shutdownAll()
}
```

---

## 스캔 타이밍

| 트리거 | 동작 |
|---|---|
| 앱 최초 실행 | 전체 서버 lazy 스캔 (Task.detached per server) |
| 상단 새로고침 버튼 | 전체 서버 lazy 스캔 |
| 서버 섹션 헤더 `↻` | 해당 서버만 재스캔 |

Lazy = 각 서버 스캔을 독립 Task로 병렬 실행. 한 서버가 느려도 다른 서버 결과가 먼저 표시됨.

---

## UI 구조

### `ServerListView` 레이아웃

```
┌─────────────────────────────────────┐
│  서버                        + 추가  │  섹션 헤더 (항상)
├─────────────────────────────────────┤
│  ● 포워딩 중                         │  포워딩 있을 때만
│    🟢 5432  postgres  prod-db        │
│    🟢 3306  mysql     dev-server     │
├─────────────────────────────────────┤
│  ▼ prod-db (192.168.1.100)  ↻  ···  │  서버 섹션 헤더
│    ○  3000  node                     │
│    ○  8080  nginx                    │
├─────────────────────────────────────┤
│  ▼ dev-server  ↻  ···               │
│    [스캔 중...]                       │
└─────────────────────────────────────┘
```

### 서버 섹션 헤더 우측 액션
- `↻` — 해당 서버만 재스캔
- `···` — 편집 / 삭제 컨텍스트 메뉴

### 인증 실패 UX

`authFailed` 상태일 때 섹션 아래 인라인 표시:

```
▼ staging (10.0.0.5)  ↻  ···
  ⚠️ SSH 키 인증 실패
     ssh-copy-id deploy@10.0.0.5     [복사]
```

`[복사]` 버튼: `NSPasteboard.general.setString()` → 일시적 "복사됨 ✓" 피드백.

### `AddServerSheet` 입력 필드

| 필드 | 필수 | 기본값 |
|---|---|---|
| 표시 이름 | 아니오 | — |
| 사용자 | 예 | — |
| 호스트 | 예 | — |
| 포트 | 아니오 | 22 |

### 포워딩 행 서버 표시

포워딩 중인 포트 행에 서버 이름을 소형 pill 뱃지로 표시:
```
🟢 5432  postgres  [prod-db]     [브라우저에서 열기]  ← 호버 시만 노출
         내 PC localhost:5432 → 리모트 5432
```

### 앱 창 크기

- `minWidth: 480`, `idealWidth: 540`
- 브라우저에서 열기 버튼 텍스트("브라우저에서 열기") + 서버 pill 뱃지 수용을 위해 기존 360→480으로 확장

---

## 이미 적용된 변경

- `ForwardingRowView`: 행 호버 시에만 "브라우저에서 열기" 버튼 노출 (`isRowHovering`)
- `ContentView`: `minWidth 360→480`, `idealWidth 420→540`

---

## 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `Models/Server.swift` | 신규 |
| `Models/Forwarding.swift` | `host→serverId+serverDisplayName` |
| `Models/SSHHost.swift` | 삭제 |
| `Storage/ServerStore.swift` | 신규 |
| `ViewModels/ServerSectionViewModel.swift` | 신규 |
| `ViewModels/AppViewModel.swift` | 대폭 수정 |
| `Views/ServerListView.swift` | 신규 |
| `Views/ServerSectionView.swift` | 신규 |
| `Views/AddServerSheet.swift` | 신규 |
| `Views/ContentView.swift` | 수정 |
| `Views/ForwardingRowView.swift` | 수정 (완료) |
| `Views/HostPickerView.swift` | 삭제 |
| `SSH/SSHConfigParser.swift` | 삭제 |
