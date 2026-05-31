import { useEffect } from "react";

import { serverDisplayName, useAppStore } from "./store/appStore";
import type { ThemeMode } from "./lib/types";
import { ServerList } from "./components/ServerList";
import { ErrorToasts } from "./components/ErrorToasts";
import { PortConflictModal } from "./components/PortConflictModal";
import "./App.css";

const THEME_LABELS: Record<ThemeMode, string> = {
  system: "자동",
  light: "라이트",
  dark: "다크",
};
const THEME_ORDER: ThemeMode[] = ["system", "light", "dark"];

/**
 * 앱 셸 — macOS `ContentView` 등가. 헤더(타이틀 + 테마 토글) + 서버 리스트 +
 * 에러 토스트 스택 + 포트충돌 모달. 마운트 시 저장 데이터 로드 후 전체 스캔/포워딩 동기화.
 */
function App() {
  const errors = useAppStore((s) => s.errors);
  const themeMode = useAppStore((s) => s.themeMode);
  const pendingPortConflict = useAppStore((s) => s.pendingPortConflict);
  const servers = useAppStore((s) => s.servers);
  const conflictServerName = pendingPortConflict
    ? serverDisplayName(servers, pendingPortConflict.serverId)
    : undefined;

  const dismissError = useAppStore((s) => s.dismissError);
  const setThemeMode = useAppStore((s) => s.setThemeMode);
  const resolveConflict = useAppStore((s) => s.resolveConflict);
  const setPendingPortConflict = useAppStore((s) => s.setPendingPortConflict);
  const loadServers = useAppStore((s) => s.loadServers);
  const loadFavorites = useAppStore((s) => s.loadFavorites);
  const loadPrefs = useAppStore((s) => s.loadPrefs);
  const scanAll = useAppStore((s) => s.scanAll);
  const refreshForwardings = useAppStore((s) => s.refreshForwardings);

  useEffect(() => {
    void (async () => {
      await Promise.all([loadServers(), loadFavorites(), loadPrefs()]);
      // 서버 로드 후에야 스캔 대상이 존재한다.
      await Promise.all([scanAll(), refreshForwardings()]);
    })();
  }, [loadServers, loadFavorites, loadPrefs, scanAll, refreshForwardings]);

  const cycleTheme = () => {
    const idx = THEME_ORDER.indexOf(themeMode);
    setThemeMode(THEME_ORDER[(idx + 1) % THEME_ORDER.length]);
  };

  return (
    <div className="pb-shell">
      <header className="pb-shell__header">
        <span className="pb-shell__title">PortBridge</span>
        <button className="pb-theme-toggle" onClick={cycleTheme} type="button">
          테마: {THEME_LABELS[themeMode]}
        </button>
      </header>

      <ServerList />

      <ErrorToasts errors={errors} onDismiss={dismissError} />

      {pendingPortConflict && (
        <PortConflictModal
          conflict={pendingPortConflict}
          serverDisplayName={conflictServerName}
          onConfirm={(newPort) => void resolveConflict(newPort)}
          onClose={() => setPendingPortConflict(null)}
        />
      )}
    </div>
  );
}

export default App;
