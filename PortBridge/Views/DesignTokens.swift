// PortBridge/Views/DesignTokens.swift
import AppKit
import SwiftUI

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
        /// (다크 #6E6E76 vs #1A1A1A ≈ 3.33:1 / 라이트 #8E8E93 vs #FFFFFF ≈ 3.26:1).
        /// 라이트는 Apple systemGray와 동일 — textBackgroundColor(흰색) 위에서 3:1 충족.
        static let inputBorder = dynamic(
            dark: NSColor(srgbRed: 110 / 255, green: 110 / 255, blue: 118 / 255, alpha: 1),
            light: NSColor(srgbRed: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
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

        // MARK: - Background

        // macOS 시스템 설정과 동일한 표면 계층. NSColor 시맨틱을 그대로 alias.
        // Tahoe에서 카드(`bgSurface`)가 캔버스(`bgCanvas`)보다 밝은 점에 유의 — iOS와 반대.

        /// 윈도우 전체 캔버스 배경.
        static let bgCanvas = Color(nsColor: .windowBackgroundColor)

        /// 그룹 카드/리스트 배경. 캔버스 위 1단계.
        static let bgSurface = Color(nsColor: .controlBackgroundColor)

        /// 카드 내부의 인셋 영역 배경 (한 단계 더 들어간 표면).
        static let bgSurfaceSecondary = Color(nsColor: .underPageBackgroundColor)

        // MARK: - Text

        // 시스템 시맨틱 — High Contrast / Increase Contrast 자동 대응 + WCAG 4.5:1 보장.

        /// 본문/타이틀.
        static let textPrimary = Color(nsColor: .labelColor)

        /// 설명/캡션 ("선호하는 …을 선택하세요" 류).
        static let textSecondary = Color(nsColor: .secondaryLabelColor)

        /// 보조 캡션 ("여러 가지 색상" 같은 미세 텍스트).
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        /// 비활성/placeholder 텍스트.
        static let textPlaceholder = Color(nsColor: .placeholderTextColor)

        // MARK: - Separator

        /// 행/섹션 구분선. Apple이 §1.4.11 Non-text Contrast 3:1을 자동 보장.
        static let separator = Color(nsColor: .separatorColor)

        // MARK: - System Accent Palette

        /// macOS 시스템 컬러 13종 — 라이트/다크 자동 분기 + Increase Contrast 대응.
        ///
        /// 사용자 선호 액센트를 따르려면 `Color.accentColor`를 쓰세요;
        /// 여기 정의된 토큰은 "특정 색"이 의미를 갖는 경우(상태/카테고리)에만.
        enum Accent {
            static let red = Color(nsColor: .systemRed)
            static let orange = Color(nsColor: .systemOrange)
            static let yellow = Color(nsColor: .systemYellow)
            static let green = Color(nsColor: .systemGreen)
            static let mint = Color(nsColor: .systemMint)
            static let teal = Color(nsColor: .systemTeal)
            static let cyan = Color(nsColor: .systemCyan)
            static let blue = Color(nsColor: .systemBlue)
            static let indigo = Color(nsColor: .systemIndigo)
            static let purple = Color(nsColor: .systemPurple)
            static let pink = Color(nsColor: .systemPink)
            static let brown = Color(nsColor: .systemBrown)
            static let gray = Color(nsColor: .systemGray)
        }

        // MARK: - Glass (Liquid Glass materials)

        /// 스크린샷의 그룹 카드/사이드바는 단일 색이 아니라 블러 머티리얼.
        ///
        /// `.background(Color.PB.Glass.regular, in: RoundedRectangle(cornerRadius: 14))` 형태로 사용.
        enum Glass {
            /// 그룹 카드 기본 (테마/윈도우/스크롤 컨테이너).
            static let regular: Material = .regular
            /// 사이드바·팝오버 등 더 두꺼운 블러.
            static let thick: Material = .thick
            /// 툴팁·플로팅 헤더 등 가벼운 블러.
            static let thin: Material = .thin
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
