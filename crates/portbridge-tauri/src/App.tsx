import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

function App() {
  const [coreVersion, setCoreVersion] = useState("…");

  useEffect(() => {
    // 아키텍처 검증: Tauri 커맨드 경유로 portbridge-core를 소비한다.
    invoke<string>("core_version")
      .then(setCoreVersion)
      .catch(() => setCoreVersion("unavailable"));
  }, []);

  return (
    <main className="container">
      <h1>PortBridge</h1>
      <p>
        portbridge-core <code>v{coreVersion}</code>
      </p>
    </main>
  );
}

export default App;
