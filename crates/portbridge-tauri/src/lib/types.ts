// 백엔드 경계(src-tauri/src/commands.rs)와 1:1 대응하는 프론트 타입.
//
// ⚠️ 직렬화 케이스가 타입마다 다르다 — 백엔드 serde 설정을 그대로 미러한다:
//   · 경계 DTO(RemotePort/ResolvedHost/Forwarding/ForwardSpec): rename_all 없음 → snake_case
//   · core Server: rename_all 없음(전부 단일 단어라 동형)
//   · core Favorite/Prefs: #[serde(rename_all = "camelCase")] → camelCase
// 케이스가 어긋나면 런타임에 조용히 undefined가 되므로 주의.

/** core `model::Server`. `name`은 serde skip_serializing_if=none → 부재 가능. */
export interface Server {
  id: string;
  name?: string;
  user: string;
  host: string;
  port: number;
}

/** `RemotePortDto` (snake_case). */
export interface RemotePort {
  port: number;
  address: string;
  process_name: string | null;
}

/** `ResolvedHostDto` (snake_case). */
export interface ResolvedHost {
  hostname: string | null;
  user: string | null;
  port: number | null;
  identity_file: string | null;
}

/** `ForwardingDto` (snake_case). `state`는 "Idle"|"Starting"|"Active"|"Error: ..." 문자열. */
export interface Forwarding {
  id: string;
  server_id: string;
  remote_port: number;
  local_port: number;
  state: string;
  activated_at_ms: number | null;
}

/** `ForwardSpecDto` 입력 (snake_case). */
export interface ForwardSpec {
  remote_port: number;
  local_port: number;
}

/** core `persistence::Favorite` (camelCase). */
export interface Favorite {
  serverId: string;
  remotePort: number;
}

/** core `persistence::Prefs` (camelCase). */
export interface Prefs {
  showInDock: boolean;
  launchAtLogin: boolean;
  automaticUpdateCheckEnabled: boolean;
}

// ── 프론트 전용 UI 상태 (macOS AppViewModel 등가, 백엔드 미경유) ──

/** macOS `ErrorToast` 등가. */
export interface ErrorToast {
  id: string;
  message: string;
}

/** macOS `PortConflict` 등가 — 로컬 포트 충돌 해소 시트 입력. */
export interface PortConflict {
  serverId: string;
  remotePort: number;
  /** 충돌난(이미 사용 중인) 로컬 포트. 사용자는 이와 다른 포트를 입력해야 한다. */
  attemptedLocal: number;
}

/** 테마 모드 (시스템/라이트/다크). */
export type ThemeMode = "system" | "light" | "dark";

/**
 * 섹션 스캔 상태 (macOS `ServerSectionViewModel.scanState` 등가).
 *
 * core `PortBridgeError`는 이미 분류돼 있으나 #106 Tauri 커맨드가 경계에서 `to_string()`으로
 * 평탄화한다. 구조화 에러 노출(백엔드 보강)이 들어오기 전까지 store는 `loaded`/`error`만 채우고,
 * `offline`/`toolMissing`/`authFailed`는 백엔드 구조화 후 채운다(뷰는 전체 상태를 미리 지원).
 * 라이브 터널 사망 이벤트는 별도 이벤트 인프라 필요 — 후속 트랙.
 */
export type ScanState =
  | { kind: "idle" }
  | { kind: "scanning" }
  | { kind: "loaded" }
  | { kind: "offline"; isRetrying: boolean }
  | { kind: "toolMissing" }
  | { kind: "authFailed"; copyCommand: string }
  | { kind: "error"; message: string };

/** macOS `ServerSectionViewModel` 등가 — 서버 + 스캔포트 + 펼침/스캔상태 결합(파생). */
export interface ServerSection {
  server: Server;
  ports: RemotePort[];
  isExpanded: boolean;
  scanState: ScanState;
}

/** ForwardingDto.state 문자열이 활성 계열(Idle 아님)인지. */
export function isActiveForwardingState(state: string): boolean {
  return state !== "Idle";
}
