// 테마 적용기 — 스토어의 themeMode를 documentElement의 data-theme(light|dark)로 반영한다.
//
// "system"이면 prefers-color-scheme를 추종하며 OS 테마 변경에 실시간 반응한다.
// tokens.css가 :root[data-theme="dark"]로 다크 토큰을 정의하므로, 여기선 속성만 토글한다.

import { useEffect, type ReactNode } from "react";

import { useAppStore } from "../store/appStore";

export function ThemeProvider({ children }: { children: ReactNode }) {
  const themeMode = useAppStore((s) => s.themeMode);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const resolved =
        themeMode === "system" ? (mq.matches ? "dark" : "light") : themeMode;
      document.documentElement.dataset.theme = resolved;
    };
    apply();

    if (themeMode === "system") {
      mq.addEventListener("change", apply);
      return () => mq.removeEventListener("change", apply);
    }
    return undefined;
  }, [themeMode]);

  return <>{children}</>;
}
