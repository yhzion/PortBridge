// 전역 상태 스토어 (Zustand) — macOS `AppViewModel`의 React 등가 **골격**.
//
// S2 범위(option ①): 상태 슬라이스 + 얇은 invoke-호출 액션(데이터 로드/저장/스캔/터널)까지.
// 복합 오케스트레이션(즐겨찾기 자동시작, 포트충돌 해소, 연결정보 변경 시 터널 재시작 등
// AppViewModel의 비자명 로직)은 화면과 함께 채우는 S3로 미룬다. 여기서는 화면이 올라탈
// 상태 형태와 백엔드 seam을 확정하는 데 집중한다.

import { create } from "zustand";

import * as api from "../lib/api";
import type {
  ErrorToast,
  Favorite,
  Forwarding,
  ForwardSpec,
  PortConflict,
  Prefs,
  RemotePort,
  ResolvedHost,
  Server,
  ThemeMode,
} from "../lib/types";

/** core `Prefs::default()`와 동일한 기본값. */
const DEFAULT_PREFS: Prefs = {
  showInDock: true,
  launchAtLogin: false,
  automaticUpdateCheckEnabled: true,
};

function toMessage(e: unknown): string {
  if (typeof e === "string") return e;
  if (e instanceof Error) return e.message;
  return String(e);
}

interface AppState {
  // ── 데이터 슬라이스 (백엔드 경유) ──
  version: string;
  servers: Server[];
  /** serverId → 스캔된 원격 포트. (macOS serverSections의 원천 데이터) */
  portsByServer: Record<string, RemotePort[]>;
  forwardings: Forwarding[];
  favorites: Favorite[];
  prefs: Prefs;

  // ── UI 슬라이스 (프론트 전용) ──
  errors: ErrorToast[];
  searchText: string;
  pendingPortConflict: PortConflict | null;
  /** serverId → 섹션 펼침 여부. */
  expanded: Record<string, boolean>;
  themeMode: ThemeMode;

  // ── 액션: 데이터 로드/저장 ──
  loadVersion: () => Promise<void>;
  loadServers: () => Promise<void>;
  saveServers: (servers: Server[]) => Promise<void>;
  addServer: (server: Server) => Promise<void>;
  updateServer: (server: Server) => Promise<void>;
  deleteServer: (id: string) => Promise<void>;
  scanServer: (server: Server) => Promise<void>;
  resolveServerAlias: (alias: string) => Promise<ResolvedHost | null>;
  loadFavorites: () => Promise<void>;
  toggleFavorite: (serverId: string, remotePort: number) => Promise<void>;
  loadPrefs: () => Promise<void>;
  savePrefs: (prefs: Prefs) => Promise<void>;

  // ── 액션: 포워딩 ──
  startForwarding: (server: Server, spec: ForwardSpec) => Promise<void>;
  stopForwarding: (id: string) => Promise<void>;
  refreshForwardings: () => Promise<void>;
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
    // 낙관적 업데이트 — 연속 호출(add/update/delete)이 await 사이에 stale `get()`을
    // 읽어 쓰기가 유실되지 않도록 로컬을 먼저 반영하고, 저장 실패 시 롤백한다.
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
  },

  updateServer: async (server) => {
    await get().saveServers(
      get().servers.map((s) => (s.id === server.id ? server : s)),
    );
  },

  deleteServer: async (id) => {
    await get().saveServers(get().servers.filter((s) => s.id !== id));
  },

  scanServer: async (server) => {
    try {
      const ports = await api.scanPorts(server);
      set({ portsByServer: { ...get().portsByServer, [server.id]: ports } });
    } catch (e) {
      get().pushError(toMessage(e));
    }
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
    // 낙관적 업데이트 — 빠른 연속 토글이 stale `get().favorites`를 읽어 꼬이지 않도록
    // 로컬을 먼저 반영하고, 저장 실패 시 롤백한다.
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
    try {
      await api.prefsSave(prefs);
      set({ prefs });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  startForwarding: async (server, spec) => {
    try {
      const fw = await api.forwardingStart(server, spec);
      set({ forwardings: [...get().forwardings, fw] });
    } catch (e) {
      get().pushError(toMessage(e));
    }
  },

  stopForwarding: async (id) => {
    try {
      await api.forwardingStop(id);
      set({ forwardings: get().forwardings.filter((f) => f.id !== id) });
    } catch (e) {
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
    set({ errors: [...get().errors, toast] });
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
    const anyCollapsed = get().servers.some((s) => !get().expanded[s.id]);
    const expanded: Record<string, boolean> = {};
    for (const s of get().servers) expanded[s.id] = anyCollapsed;
    set({ expanded });
  },

  setThemeMode: (mode) => set({ themeMode: mode }),
}));
