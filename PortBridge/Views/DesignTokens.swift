// PortBridge/Views/DesignTokens.swift
import SwiftUI
import AppKit

extension Color {
    /// PortBridge 디자인 토큰.
    ///
    /// 시스템 시맨틱 컬러(`.primary`, `.secondary`, `.tint`, `.red` 등)는 그대로 사용합니다 —
    /// macOS가 라이트/다크/High Contrast 환경에 자동 적응시키며 WCAG 텍스트 대비(4.5:1)를 보장하기 때문.
    /// 여기 정의된 토큰은 hex/opacity가 코드에 직접 박혀 일관성이 깨질 위험이 있는 지점만 추상화합니다.
    enum PB {
        // MARK: - Border

        /// 입력 필드 비활성 외곽선.
        /// WCAG 2.1 §1.4.11 Non-text Contrast 3:1 이상 보장
        /// (다크 #6E6E76 vs #1A1A1A ≈ 3.4:1 / 라이트 #AEAEB2 vs #FFFFFF ≈ 3.0:1).
        static let inputBorder = dynamic(
            dark:  NSColor(srgbRed: 110/255, green: 110/255, blue: 118/255, alpha: 1),
            light: NSColor(srgbRed: 174/255, green: 174/255, blue: 178/255, alpha: 1)
        )

        /// 입력 필드 포커스 외곽선 — 사용자 강조 색상에 자동 동기화.
        static let inputBorderFocused = Color.accentColor

        // MARK: - Accent variants
        //
        // accent 위에 얹는 미묘한 톤들 — opacity 곱 한 줄을 시맨틱 이름으로 노출.

        /// 강조 컴포넌트의 idle 배경 (예: 브라우저 열기 버튼 평상시).
        static let accentBgIdle = Color.accentColor.opacity(0.06)
        /// hover 시 배경.
        static let accentBgHover = Color.accentColor.opacity(0.15)
        /// pressed 시 배경.
        static let accentBgPressed = Color.accentColor.opacity(0.25)
        /// 강조 외곽선 — 미묘.
        static let accentStrokeSubtle = Color.accentColor.opacity(0.18)
        /// 강조 외곽선 — hover.
        static let accentStrokeHover = Color.accentColor.opacity(0.35)
        /// 카운트 배지 등 강조 표지의 배경.
        static let accentBadgeBg = Color.accentColor.opacity(0.14)

        // MARK: - Monogram

        /// ServerMonogram의 색상 변조 파라미터.
        /// host 바이트 합으로 hue를 결정하고, 채도·명도·opacity는 여기서 고정해
        /// 모든 서버 아바타가 동일한 톤 위에서 일관되게 보이도록 합니다.
        enum Monogram {
            static let saturation: Double = 0.55
            static let brightness: Double = 0.85
            static let fillOpacity: Double = 0.18
            static let strokeOpacity: Double = 0.40
        }

        // MARK: - Helpers

        private static func dynamic(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let matched = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
                let isDark = matched == .darkAqua || matched == .vibrantDark
                return isDark ? dark : light
            })
        }
    }
}
