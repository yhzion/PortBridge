// 전역 상태 스토어 (Zustand) — macOS `AppViewModel`의 React 등가.
//
// S2(#107)는 상태 슬라이스 + 얇은 invoke 래퍼만 깔았고, S3(#108)에서 화면이 요구하는
// 오케스트레이션(섹션 파생·활성 포워딩·검색 매칭·토글/충돌 흐름·에러 자동소멸)을 흡수한다.
//
// 백엔드 모델 차이: #106 `forwarding_start`는 1500ms settle 후 블로킹 반환(Active/err-string)이라
// macOS의 낙관적 placeholder→비동기 갱신 모델을 await 동안의 "Starting" 표시로 근사한다.
// 라이브 터널 사망 이벤트는 백엔드 이벤트 인프라 부재로 미반영(후속 트랙).

import { create } from "zustand";

import * as api from "../lib/api";
import {
  isActiveForwardingState,
  type ErrorToast,
  type Favorite,
  type Forwarding,
  type ForwardSpec,
  type PortConflict,
  type Prefs,
  type RemotePort,
  type ResolvedHost,
  type ScanState,
  type Server,
  type ServerSection,
  type ThemeMode,
} from "../lib/types";

/** core `Prefs::default()`와 동일한 기본값. */
const DEFAULT_PREFS: Prefs = {
  showInDock: true,
  launchAtLogin: false,
  automaticUpdateCheckEnabled: true,
};

/** macOS AppViewModel: 최대 3개 토스트, 5초 후 자동 소멸. */
const MAX_ERRORS = 3;
const ERROR_TTL_MS = 5000;

function toMessage(e: unknown): string {
  if (typeof e === "string") return e;
  if (e instanceof Error) return e.message;
  return String(e);
}

interface AppState {
  // ── 데이터 슬라이스 (백엔드 경유) ──
  version: string;
  servers: Server[];
  /** serverId → 스캔된 원격 포트. */
  portsByServer: Record<string, RemotePort[]>;
  /** serverId → 스캔 상태. */
  scanStateByServer: Record<string, ScanState>;
  forwardings: Forwarding[];
  favorites: Favorite[];
  prefs: Prefs;

  // ── UI 슬라이스 (프론트 전용) ──
  errors: ErrorToast[];
  searchText: string;
  pendingPortConflict: PortConflict | null;
  /** serverId → 섹션 펼침 여부(미설정 시 펼침). */
  expanded: Record<string, boolean>;
  themeMode: ThemeMode;

  // ── 액션: 데이터 로드/저장 ──
  loadVersion: () => Promise<void>;
  loadServers: () => Promise<void>;
  saveServers: (servers: Server[]) => Promise<void>;
  addServer: (server: Server) => Promise<void>;
  updateServer: (server: Server) => Promise<void>;
  deleteServer: (id: string) => Promise<void>;
  resolveServerAlias: (alias: string) => Promise<ResolvedHost | null>;
  loadFavorites: () => Promise<void>;
  toggleFavorite: (serverId: string, remotePort: number) => Promise<void>;
  loadPrefs: () => Promise<void>;
  savePrefs: (prefs: Prefs) => Promise<void>;

  // ── 액션: 스캔 ──
  scanServer: (server: Server) => Promise<void>;
  scanAll: () => Promise<void>;

  // ── 액션: 포워딩 ──
  beginForwarding: (
    server: Server,
    remotePort: number,
    localPort: number,
  ) => Promise<void>;
  toggleForwarding: (serverId: string, remotePort: number) => Promise<void>;
  stopForwarding: (id: string) => Promise<void>;
  refreshForwardings: () => Promise<void>;
  resolveConflict: (newLocalPort: number) => Promise<void>;
  stopAllActiveForwardings: () => Promise<void>;
  previewForwardArgs: (server: Server, spec: ForwardSpec) => Promise<string[]>;

  // ── 액션: UI 상태 ──
  pushError: (message: string) => void;
  dismissError: (id: string) => void;
  setSearchText: (text: string) => void;
  setPendingPortConflict: (conflict: PortConflict | null) => void;
  setExpanded: (serverId: string, value: boolean) => void;
  toggleAllExpanded: () => void;
  setThemeMode: (mode: ThemeMode) => void;
}

export const useAppStore = create<AppState>()((set, get) => ({
  version: "",
  servers: [],
  portsByServer: {},
  scanStateByServer: {},
  forwardings: [],
  favorites: [],
  prefs: DEFAULT_PREFS,

  errors: [],
  searchText: "",
  pendingPortConflict: null,
  expanded: {},
  themeMode: "system",

  loadVersion: async () => {
    try {
      set({ version: await api.coreVersion() });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  loadServers: async () => {
    try {
      set({ servers: await api.serverList() });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  saveServers: async (servers) => {
    // 낙관적 업데이트 — 연속 호출이 await 사이 stale get()을 읽어 쓰기 유실되지 않도록.
    const prev = get().servers;
    set({ servers });
    try {
      await api.serverSave(servers);
    } catch (e) {
      set({ servers: prev });
      get().pushError(toMessage(e));
    }
  },

  addServer: async (server) => {
    await get().saveServers([...get().servers, server]);
    await get().scanServer(server);
  },

  updateServer: async (server) => {
    await get().saveServers(
      get().servers.map((s) => (s.id === server.id ? server : s)),
    );
    await get().scanServer(server);
  },

  deleteServer: async (id) => {
    // 활성 포워딩 먼저 정리한 뒤 서버 제거(macOS stopAll → store.delete 순서).
    for (const f of get().forwardings.filter((x) => x.server_id === id)) {
      await get().stopForwarding(f.id);
    }
    await get().saveServers(get().servers.filter((s) => s.id !== id));
  },

  resolveServerAlias: async (alias) => {
    try {
      return await api.resolveAlias(alias);
    } catch (e) {
      get().pushError(toMessage(e));
      return null;
    }
  },

  loadFavorites: async () => {
    try {
      set({ favorites: await api.favoritesList() });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  toggleFavorite: async (serverId, remotePort) => {
    const prev = get().favorites;
    const exists = prev.some(
      (f) => f.serverId === serverId && f.remotePort === remotePort,
    );
    const next: Favorite[] = exists
      ? prev.filter(
          (f) => !(f.serverId === serverId && f.remotePort === remotePort),
        )
      : [...prev, { serverId, remotePort }];
    set({ favorites: next });
    try {
      await api.favoritesSave(next);
    } catch (e) {
      set({ favorites: prev });
      get().pushError(toMessage(e));
    }
  },

  loadPrefs: async () => {
    try {
      set({ prefs: await api.prefsLoad() });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  savePrefs: async (prefs) => {
    const prev = get().prefs;
    set({ prefs });
    try {
      await api.prefsSave(prefs);
    } catch (e) {
      set({ prefs: prev });
      get().pushError(toMessage(e));
    }
  },

  scanServer: async (server) => {
    set({
      scanStateByServer: {
        ...get().scanStateByServer,
        [server.id]: { kind: "scanning" },
      },
    });
    try {
      const ports = await api.scanPorts(server);
      set({
        portsByServer: { ...get().portsByServer, [server.id]: ports },
        scanStateByServer: {
          ...get().scanStateByServer,
          [server.id]: { kind: "loaded" },
        },
      });
    } catch (e) {
      // TODO(백엔드 구조화 에러): 현재 커맨드가 PortBridgeError를 문자열로 평탄화하므로
      // offline/toolMissing/authFailed로 분류 불가 → 구조화 에러 노출 후 채운다.
      set({
        scanStateByServer: {
          ...get().scanStateByServer,
          [server.id]: { kind: "error", message: toMessage(e) },
        },
      });
    }
  },

  scanAll: async () => {
    await Promise.all(get().servers.map((s) => get().scanServer(s)));
  },

  beginForwarding: async (server, remotePort, localPort) => {
    // await 동안 "Starting"을 표시할 placeholder. 백엔드가 settle 후 실제 dto를 반환하면 교체.
    const placeholderId = `pending-${crypto.randomUUID()}`;
    const placeholder: Forwarding = {
      id: placeholderId,
      server_id: server.id,
      remote_port: remotePort,
      local_port: localPort,
      state: "Starting",
      activated_at_ms: Date.now(),
    };
    set({ forwardings: [...get().forwardings, placeholder] });
    try {
      const fw = await api.forwardingStart(server, {
        remote_port: remotePort,
        local_port: localPort,
      });
      set({
        forwardings: get().forwardings.map((f) =>
          f.id === placeholderId ? fw : f,
        ),
      });
    } catch (e) {
      set({
        forwardings: get().forwardings.filter((f) => f.id !== placeholderId),
      });
      const msg = toMessage(e);
      if (/address already in use/i.test(msg)) {
        set({
          pendingPortConflict: {
            serverId: server.id,
            remotePort,
            attemptedLocal: localPort,
          },
        });
      } else {
        get().pushError(msg);
      }
    }
  },

  toggleForwarding: async (serverId, remotePort) => {
    const existing = get().forwardings.find(
      (f) => f.server_id === serverId && f.remote_port === remotePort,
    );
    if (existing) {
      await get().stopForwarding(existing.id);
      return;
    }
    const server = get().servers.find((s) => s.id === serverId);
    if (!server) return;
    await get().beginForwarding(server, remotePort, remotePort);
  },

  stopForwarding: async (id) => {
    const prev = get().forwardings;
    set({ forwardings: prev.filter((f) => f.id !== id) });
    try {
      await api.forwardingStop(id);
    } catch (e) {
      set({ forwardings: prev });
      get().pushError(toMessage(e));
    }
  },

  refreshForwardings: async () => {
    try {
      set({ forwardings: await api.forwardingList() });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  resolveConflict: async (newLocalPort) => {
    const pending = get().pendingPortConflict;
    if (!pending) return;
    set({ pendingPortConflict: null });
    const server = get().servers.find((s) => s.id === pending.serverId);
    if (!server) return;
    await get().beginForwarding(server, pending.remotePort, newLocalPort);
  },

  stopAllActiveForwardings: async () => {
    const active = get().forwardings.filter((f) =>
      isActiveForwardingState(f.state),
    );
    await Promise.all(active.map((f) => get().stopForwarding(f.id)));
  },

  previewForwardArgs: async (server, spec) => {
    try {
      return await api.forwardArgsPreview(server, spec);
    } catch (e) {
      get().pushError(toMessage(e));
      return [];
    }
  },

  pushError: (message) => {
    const toast: ErrorToast = { id: crypto.randomUUID(), message };
    set({ errors: [...get().errors, toast].slice(-MAX_ERRORS) });
    setTimeout(() => get().dismissError(toast.id), ERROR_TTL_MS);
  },

  dismissError: (id) => {
    set({ errors: get().errors.filter((t) => t.id !== id) });
  },

  setSearchText: (text) => set({ searchText: text }),

  setPendingPortConflict: (conflict) => set({ pendingPortConflict: conflict }),

  setExpanded: (serverId, value) => {
    set({ expanded: { ...get().expanded, [serverId]: value } });
  },

  toggleAllExpanded: () => {
    const allExpanded = get().servers.every(
      (s) => get().expanded[s.id] ?? true,
    );
    const next: Record<string, boolean> = {};
    for (const s of get().servers) next[s.id] = !allExpanded;
    set({ expanded: next });
  },

  setThemeMode: (mode) => set({ themeMode: mode }),
}));

// ── 파생 셀렉터 ──
//
// ⚠️ zustand v5: useAppStore(selector)의 selector가 매번 새 참조(배열/객체/클로저)를 반환하면
// 무한 재렌더(React #185)가 난다. 따라서 이 셀렉터들은 **원시 슬라이스를 인자로 받는 순수 함수**이며,
// 컴포넌트는 슬라이스만 구독(useAppStore((s)=>s.servers) 등 — 안정 참조)한 뒤 useMemo로 파생한다.

/** 서버 + 스캔포트 + 펼침/스캔상태 결합. 미설정 섹션은 펼침·idle 기본. */
export function selectServerSections(
  servers: Server[],
  portsByServer: Record<string, RemotePort[]>,
  expanded: Record<string, boolean>,
  scanStateByServer: Record<string, ScanState>,
): ServerSection[] {
  return servers.map((server) => ({
    server,
    ports: portsByServer[server.id] ?? [],
    isExpanded: expanded[server.id] ?? true,
    scanState: scanStateByServer[server.id] ?? { kind: "idle" },
  }));
}

/** 활성 계열(Idle 아님) 포워딩을 활성화 시각 내림차순으로. */
export function selectActiveForwardings(
  forwardings: Forwarding[],
): Forwarding[] {
  return forwardings
    .filter((f) => isActiveForwardingState(f.state))
    .sort((a, b) => (b.activated_at_ms ?? 0) - (a.activated_at_ms ?? 0));
}

/** 모든 섹션이 펼쳐졌는지(allExpanded). */
export function selectAllExpanded(
  servers: Server[],
  expanded: Record<string, boolean>,
): boolean {
  return servers.every((server) => expanded[server.id] ?? true);
}

/** 검색어 → 포트 매칭 함수(포트번호 부분일치 또는 프로세스명 부분일치). */
export function makeMatches(searchText: string): (port: RemotePort) => boolean {
  const q = searchText.trim().toLowerCase();
  return (port) => {
    if (!q) return true;
    if (String(port.port).includes(q)) return true;
    return port.process_name?.toLowerCase().includes(q) ?? false;
  };
}

/** 즐겨찾기 여부. */
export function isFavorite(
  favorites: Favorite[],
  serverId: string,
  remotePort: number,
): boolean {
  return favorites.some(
    (f) => f.serverId === serverId && f.remotePort === remotePort,
  );
}

/** 서버 표시명(name ?? host). */
export function serverDisplayName(
  servers: Server[],
  serverId: string,
): string | undefined {
  const sv = servers.find((x) => x.id === serverId);
  return sv ? (sv.name ?? sv.host) : undefined;
}
