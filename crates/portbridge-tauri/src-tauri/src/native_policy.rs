//! 네이티브 폴리시(#133) — macOS 메뉴바 앱 등가 동작의 Tauri 측 구현.
//!
//! macOS 앱(`MenuBarController`/`AppPreferences`)의 dock 정책·동적 트레이 아이콘을
//! Tauri로 옮긴다. Tauri 비의존 순수 결정 로직(`activation_policy_for`/`any_active`/
//! `glyph_rgba`)은 단위 테스트하고, 런타임 글루(`apply_dock_policy`/`update_tray_icon`)는
//! 빌드 검증만(트레이/dock 실동작은 실 macOS 수동 검증 — #110/TESTING.md).

use tauri::image::Image;
use tauri::AppHandle;

use portbridge_core::model::{Forwarding, State};

#[cfg(target_os = "macos")]
use tauri::ActivationPolicy;

/// 트레이 글리프 한 변 픽셀(정사각, 템플릿). 시스템이 메뉴바에 맞게 스케일.
const GLYPH_SIDE: i32 = 44;

/// `show_in_dock` → macOS activation policy. `Regular`=dock 표시, `Accessory`=숨김.
/// (macOS 전용: `ActivationPolicy` 타입 자체가 `#[cfg(target_os = "macos")]`.)
#[cfg(target_os = "macos")]
pub fn activation_policy_for(show_in_dock: bool) -> ActivationPolicy {
    if show_in_dock {
        ActivationPolicy::Regular
    } else {
        ActivationPolicy::Accessory
    }
}

/// 활성 포워딩 존재 여부 — 트레이 아이콘 active/idle 결정(소비처 상태에서 파생).
pub fn any_active(forwardings: &[Forwarding]) -> bool {
    forwardings.iter().any(|f| f.state == State::Active)
}

/// 트레이 글리프(아치+베이스, active 시 중앙 점)를 RGBA 템플릿 버퍼로 그린다.
/// macOS `MenuBarIconView`가 Canvas로 프로그래밍 렌더하는 것과 동형(정적 PNG 대신).
/// 템플릿이므로 RGB=0, 알파만 커버리지로 채운다(시스템이 메뉴바 색에 맞춰 틴트).
///
/// 주의: 모양은 best-effort이며 헤드리스 환경에서 시각 확인 불가 → 실 macOS 수동 검토 대상.
pub fn glyph_rgba(active: bool) -> Vec<u8> {
    let side = GLYPH_SIDE;
    let mut buf = vec![0u8; (side * side * 4) as usize];

    // 알파만 켠다(RGB=0, 템플릿). 범위 밖은 무시.
    fn ink(buf: &mut [u8], side: i32, x: i32, y: i32) {
        if x < 0 || x >= side || y < 0 || y >= side {
            return;
        }
        let i = ((y * side + x) * 4) as usize;
        buf[i + 3] = 255;
    }

    // 베이스 데크(하단 수평 바).
    for y in 30..34 {
        for x in 7..37 {
            ink(&mut buf, side, x, y);
        }
    }
    // 아치(상단 반원 링 밴드), 중심 (22,32), 반지름 13..16의 위쪽 절반.
    let (cx, cy) = (22i32, 32i32);
    for y in 12..=cy {
        for x in 6..38 {
            let (dx, dy) = (x - cx, y - cy);
            let d2 = dx * dx + dy * dy;
            if (13 * 13..=16 * 16).contains(&d2) {
                ink(&mut buf, side, x, y);
            }
        }
    }
    // active: 아치 아래 중앙에 채운 점.
    if active {
        let (dotx, doty, r) = (22i32, 21i32, 3i32);
        for y in (doty - r)..=(doty + r) {
            for x in (dotx - r)..=(dotx + r) {
                let (dx, dy) = (x - dotx, y - doty);
                if dx * dx + dy * dy <= r * r {
                    ink(&mut buf, side, x, y);
                }
            }
        }
    }
    buf
}

/// 로드된 dock 정책을 적용(macOS 전용; 다른 OS는 호출 자체가 없음).
#[cfg(target_os = "macos")]
pub fn apply_dock_policy(app: &AppHandle, show_in_dock: bool) {
    let _ = app.set_activation_policy(activation_policy_for(show_in_dock));
}

/// 활성 상태에 따라 트레이 아이콘을 교체한다. 트레이 미존재 시 무시.
pub fn update_tray_icon(app: &AppHandle, active: bool) {
    if let Some(tray) = app.tray_by_id("main-tray") {
        let rgba = glyph_rgba(active);
        let img = Image::new(&rgba, GLYPH_SIDE as u32, GLYPH_SIDE as u32);
        let _ = tray.set_icon_with_as_template(Some(img), true);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::SystemTime;

    fn fwd(state: State) -> Forwarding {
        Forwarding {
            id: "x".to_string(),
            server_id: "s".to_string(),
            remote_port: 1,
            local_port: 2,
            state,
            activated_at: Some(SystemTime::UNIX_EPOCH),
        }
    }

    #[test]
    fn any_active_true_only_when_some_active() {
        assert!(!any_active(&[]));
        assert!(!any_active(&[fwd(State::Starting), fwd(State::Idle)]));
        assert!(any_active(&[fwd(State::Idle), fwd(State::Active)]));
    }

    #[test]
    fn glyph_has_expected_size_and_active_has_more_ink() {
        let idle = glyph_rgba(false);
        let active = glyph_rgba(true);
        let expected = (GLYPH_SIDE * GLYPH_SIDE * 4) as usize;
        assert_eq!(idle.len(), expected);
        assert_eq!(active.len(), expected);
        let ink = |b: &[u8]| b.chunks(4).filter(|p| p[3] > 0).count();
        assert!(ink(&idle) > 0, "idle 글리프에 잉크가 있어야(아치+베이스)");
        assert!(
            ink(&active) > ink(&idle),
            "active는 중앙 점이 더해져 idle보다 잉크가 많아야"
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn activation_policy_maps_dock_flag() {
        assert!(matches!(
            activation_policy_for(true),
            ActivationPolicy::Regular
        ));
        assert!(matches!(
            activation_policy_for(false),
            ActivationPolicy::Accessory
        ));
    }
}
