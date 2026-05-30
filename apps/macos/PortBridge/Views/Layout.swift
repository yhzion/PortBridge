// PortBridge/Views/Layout.swift
import SwiftUI

/// PortBridge 레이아웃 토큰.
///
/// macOS 시스템 설정(Liquid Glass)에서 관측된 spacing/radius 값.
/// `Color.PB`와 페어로, 매직 넘버(`cornerRadius: 6`, `spacing: 8` 등)가
/// 코드에 흩어져 통일성이 깨지는 걸 막기 위한 추상화.
///
/// **Typography는 의도적으로 제외**: 코드베이스가 이미 `.caption`/`.body`/`.headline` 등
/// 시스템 시맨틱 폰트를 일관 사용 중이며, Dynamic Type / 접근성 폰트 크기에 자동 반응합니다.
/// 별도 `Font.PB` 토큰을 만들면 source of truth가 둘로 나뉘고 접근성 이점을 잃습니다.
enum PBLayout {
    /// 코너 라디우스 (pt 단위).
    enum Radius {
        /// 작은 둥근 컨테이너 — 칩·배지·인라인 라벨·monogram·작은 액션 row 등.
        static let sm: CGFloat = 6
        /// 컨트롤 미리보기 카드 (라이트/다크/자동 같은 선택 카드).
        static let md: CGFloat = 10
        /// 그룹 컨테이너 (테마/윈도우/스크롤 같은 섹션 카드).
        static let lg: CGFloat = 14
        /// 윈도우 외곽.
        static let xl: CGFloat = 22
    }

    /// 간격 토큰. 4pt 베이스 스케일.
    enum Space {
        /// 4pt — 미세 간격 (행 안 라벨 사이).
        static let s1: CGFloat = 4
        /// 8pt — 컬러 스와치·아이콘 간격, 가로 HStack 기본.
        static let s2: CGFloat = 8
        /// 12pt — 행 vertical padding 또는 그룹 내 vertical 간격.
        static let s3: CGFloat = 12
        /// 16pt — 카드 내부 padding.
        static let s4: CGFloat = 16
        /// 20pt — 섹션 사이 vertical 간격.
        static let s5: CGFloat = 20
        /// 28pt — 윈도우 외곽 여백.
        static let s6: CGFloat = 28
    }
}
