// 아키텍처 검증: Tauri 백엔드가 portbridge-core를 네이티브 직접 소비함을 증명한다.
//
// 커맨드·어댑터(scan/resolve/persistence/forwarding)는 commands.rs와 어댑터 모듈에 있다.
// 이 모듈들을 마운트하고 활성 터널 상태(AppState)를 보유한 뒤, React가 invoke로 호출할
// 전체 커맨드 표면을 invoke_handler에 등록한다(#106 §8 수용 기준).
mod commands;
mod scan_runner;
mod store;
mod tunnel_runtime;

use commands::AppState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            commands::core_version,
            commands::scan_ports,
            commands::resolve_alias,
            commands::server_list,
            commands::server_save,
            commands::favorites_list,
            commands::favorites_save,
            commands::prefs_load,
            commands::prefs_save,
            commands::forwarding_start,
            commands::forwarding_stop,
            commands::forwarding_list,
            commands::forward_args_preview,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
