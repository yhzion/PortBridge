// Tauri 백엔드 진입 — portbridge-core 네이티브 소비(commands) + OS 통합(트레이/팝오버/플러그인).
//
// 커맨드·어댑터(scan/resolve/persistence/forwarding)는 commands.rs와 어댑터 모듈에 있다(#106/#107).
// S4(#109): macOS 메뉴바 등가 — 트레이 아이콘 + frameless 팝오버 윈도우(좌클릭 토글, blur 자동 숨김)
// + single-instance + autostart(Launch at Login) 플러그인 와이어링.
//
// 후속 트랙:
// - autostart enable/disable 토글: launchAtLogin 설정 UI가 생기면 플러그인 API로 연결.
// - 동적 active 트레이 아이콘(에셋 2종), 정밀 팝오버 위치, dock 정책, 업데이트 체크(코드사이닝/HTTP).

mod commands;
mod scan_runner;
mod store;
mod tunnel_runtime;

use commands::AppState;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};
use tauri_plugin_autostart::MacosLauncher;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // single-instance는 반드시 첫 플러그인.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(AppState::default())
        .setup(|app| {
            // 트레이 메뉴(우클릭): 열기 / 종료.
            let show_item = MenuItem::with_id(app, "show", "열기", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_item, &quit_item])?;

            TrayIconBuilder::with_id("main-tray")
                .icon(app.default_window_icon().expect("default icon").clone())
                .icon_as_template(true)
                .tooltip("PortBridge")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    // 좌클릭(릴리즈) → 팝오버 토글(메뉴바 동작).
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // 메인 윈도우를 팝오버로: 시작 시 숨김 + blur(포커스 잃음) 시 자동 숨김.
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.hide();
                let hide_target = window.clone();
                window.on_window_event(move |event| {
                    if let WindowEvent::Focused(focused) = event {
                        if !*focused {
                            let _ = hide_target.hide();
                        }
                    }
                });
            }

            Ok(())
        })
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
