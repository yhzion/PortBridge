// 아키텍처 검증: Tauri 백엔드가 portbridge-core를 네이티브 직접 소비함을 증명한다.
#[tauri::command]
fn core_version() -> String {
    portbridge_core::version().to_string()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![core_version])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
