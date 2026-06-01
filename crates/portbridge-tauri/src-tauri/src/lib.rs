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
mod native_policy;
mod scan_runner;
mod store;
mod tunnel_runtime;
mod update_check;

use commands::AppState;
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};

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
            // autostart 실제 등록 상태(플러그인이 SSOT) — 메뉴 체크 초기값.
            let autostart_on = app.autolaunch().is_enabled().unwrap_or(false);
            // 저장된 dock 정책(macOS 전용) — 메뉴 체크 초기값 + 시작 시 적용.
            #[cfg(target_os = "macos")]
            let prefs =
                crate::store::load_prefs(&commands::open_store(app.handle())).unwrap_or_default();

            // 트레이 메뉴(우클릭): 열기 / [Dock에 표시(macOS)] / 로그인 시 실행 / 종료.
            let show_item = MenuItem::with_id(app, "show", "열기", true, None::<&str>)?;
            let login_item = CheckMenuItem::with_id(
                app,
                "toggle_login",
                "로그인 시 실행",
                true,
                autostart_on,
                None::<&str>,
            )?;
            let update_item =
                MenuItem::with_id(app, "check_update", "업데이트 확인", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
            #[cfg(target_os = "macos")]
            let dock_item = CheckMenuItem::with_id(
                app,
                "toggle_dock",
                "Dock에 표시",
                true,
                prefs.show_in_dock,
                None::<&str>,
            )?;

            #[cfg(target_os = "macos")]
            let menu = Menu::with_items(
                app,
                &[
                    &show_item,
                    &dock_item,
                    &login_item,
                    &update_item,
                    &quit_item,
                ],
            )?;
            #[cfg(not(target_os = "macos"))]
            let menu = Menu::with_items(app, &[&show_item, &login_item, &update_item, &quit_item])?;

            // 핸들러에서 체크 상태를 갱신하려면 항목 핸들 클론을 캡처(CheckMenuItem은 Clone).
            let login_h = login_item.clone();
            #[cfg(target_os = "macos")]
            let dock_h = dock_item.clone();

            TrayIconBuilder::with_id("main-tray")
                .icon(app.default_window_icon().expect("default icon").clone())
                .icon_as_template(true)
                .tooltip("PortBridge")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    // 로그인 시 실행 토글: 플러그인 enable/disable → prefs 반영 → 체크 갱신.
                    "toggle_login" => {
                        let mgr = app.autolaunch();
                        let currently = mgr.is_enabled().unwrap_or(false);
                        let _ = if currently {
                            mgr.disable()
                        } else {
                            mgr.enable()
                        };
                        let now = mgr.is_enabled().unwrap_or(!currently);
                        let store = commands::open_store(app);
                        let mut prefs = crate::store::load_prefs(&store).unwrap_or_default();
                        prefs.launch_at_login = now;
                        let _ = crate::store::save_prefs(&store, &prefs);
                        let _ = login_h.set_checked(now);
                    }
                    // Dock 표시 토글(macOS): prefs 반전 → 정책 적용 → 체크 갱신.
                    #[cfg(target_os = "macos")]
                    "toggle_dock" => {
                        let store = commands::open_store(app);
                        let mut prefs = crate::store::load_prefs(&store).unwrap_or_default();
                        prefs.show_in_dock = !prefs.show_in_dock;
                        let _ = crate::store::save_prefs(&store, &prefs);
                        crate::native_policy::apply_dock_policy(app, prefs.show_in_dock);
                        let _ = dock_h.set_checked(prefs.show_in_dock);
                    }
                    // 수동 업데이트 확인: core check_update → 새 버전이면 릴리스 페이지 열기.
                    // 비교 대상은 앱 버전(tauri.conf.json) — core::version()(0.0.0) 아님.
                    "check_update" => {
                        crate::update_check::check_now(&app.package_info().version.to_string())
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

            // 시작 시 저장된 dock 정책 적용(macOS).
            #[cfg(target_os = "macos")]
            crate::native_policy::apply_dock_policy(app.handle(), prefs.show_in_dock);
            // 초기 트레이 아이콘 = idle 글리프(이후 forwarding 상태에 따라 교체).
            crate::native_policy::update_tray_icon(app.handle(), false);

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
