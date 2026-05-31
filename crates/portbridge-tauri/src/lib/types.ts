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
  suggestedLocalPort: number;
}

/** 테마 모드 (시스템/라이트/다크). */
export type ThemeMode = "system" | "light" | "dark";
