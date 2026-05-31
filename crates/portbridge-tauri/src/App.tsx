import { useEffect } from "react";

import { useAppStore } from "./store/appStore";
import type { ThemeMode } from "./lib/types";
import "./App.css";

const THEME_LABELS: Record<ThemeMode, string> = {
  system: "자동",
  light: "라이트",
  dark: "다크",
};
const THEME_ORDER: ThemeMode[] = ["system", "light", "dark"];

/**
 * 앱 셸(헤더/콘텐츠/푸터 + 에러 토스트 스택)의 골격.
 *
 * S2에서는 기반구조가 살아있음을 증명하는 최소 셸이다 — 마운트 시 백엔드 커맨드를 호출해
 * 스토어를 채우고, 테마 토글로 ThemeProvider 경로를 검증한다. 실제 화면(ServerList/Section/
 * ForwardingRow/AddServer/PortConflict)은 S3가 `pb-shell__content` 자리를 채운다.
 */
function App() {
  const version = useAppStore((s) => s.version);
  const servers = useAppStore((s) => s.servers);
  const forwardings = useAppStore((s) => s.forwardings);
  const errors = useAppStore((s) => s.errors);
  const themeMode = useAppStore((s) => s.themeMode);
  const dismissError = useAppStore((s) => s.dismissError);
  const setThemeMode = useAppStore((s) => s.setThemeMode);
  const loadVersion = useAppStore((s) => s.loadVersion);
  const loadServers = useAppStore((s) => s.loadServers);
  const loadFavorites = useAppStore((s) => s.loadFavorites);
  const loadPrefs = useAppStore((s) => s.loadPrefs);
  const refreshForwardings = useAppStore((s) => s.refreshForwardings);

  useEffect(() => {
    void loadVersion();
    void loadServers();
    void loadFavorites();
    void loadPrefs();
    void refreshForwardings();
  }, [loadVersion, loadServers, loadFavorites, loadPrefs, refreshForwardings]);

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

      {errors.length > 0 && (
        <div className="pb-toasts">
          {errors.map((t) => (
            <div key={t.id} className="pb-toast" role="alert">
              <span>{t.message}</span>
              <button
                className="pb-toast__dismiss"
                onClick={() => dismissError(t.id)}
                type="button"
                aria-label="에러 닫기"
              >
                ✕
              </button>
            </div>
          ))}
        </div>
      )}

      <main className="pb-shell__content">
        <p className="pb-placeholder">
          기반구조(디자인 토큰·테마·상태 스토어·invoke 래퍼) 준비 완료. 화면은
          S3에서 구현됩니다.
        </p>
        <dl className="pb-stats">
          <div>
            <dt>core</dt>
            <dd>v{version || "…"}</dd>
          </div>
          <div>
            <dt>서버</dt>
            <dd>{servers.length}</dd>
          </div>
          <div>
            <dt>활성 터널</dt>
            <dd>{forwardings.length}</dd>
          </div>
        </dl>
      </main>

      <footer className="pb-shell__footer">PortBridge · Tauri</footer>
    </div>
  );
}

export default App;
