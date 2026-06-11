import Foundation

/// UI 문자열 단일 진실 원천(SSoT).
///
/// 메뉴바와 업데이트 다이얼로그처럼 메인 윈도우와 어휘가 갈라질 수 있는 표면의 문자열을 집약합니다.
/// 추후 String Catalog(.xcstrings) 이행 시 이 파일이 이행 단위가 됩니다.
enum L10n {
    enum MenuBar {
        static let favorites = "즐겨찾기"
        static let active = "활성"
        static let emptyFavoritesHint = "메인 창에서 ★를 눌러 즐겨찾기를 추가하세요"
        static let openMainWindow = "메인 창 열기"
        static let launchAtLogin = "로그인 시 시작"
        static let showInDock = "Dock에 표시"
        static let checkUpdatesAutomatically = "자동으로 업데이트 확인"
        static let checking = "확인 중…"
        static let checkUpdatesNow = "지금 업데이트 확인…"
        static let quit = "PortBridge 종료"

        static func errorCount(_ count: Int) -> String {
            "오류 \(count)개"
        }

        static func batchToggleTitle(activeCount: Int, total: Int) -> String {
            activeCount > 0
                ? "모든 즐겨찾기 끄기 (\(activeCount)개 활성)"
                : "모든 즐겨찾기 켜기 (\(total)개)"
        }
    }

    enum Updates {
        static let upToDateTitle = "PortBridge가 최신 버전입니다"
        static let ok = "확인"
        static let checkFailedTitle = "업데이트를 확인할 수 없습니다"
        static let download = "다운로드"
        static let remindLater = "나중에 알림"
        static let skipThisVersion = "이 버전 건너뛰기"
        static let availableFallbackMessage = "새 버전이 있습니다. 다운로드를 누르면 릴리스 페이지가 열립니다."

        static func upToDateMessage(version: String) -> String {
            "현재 최신 버전(\(version))을 사용 중입니다."
        }

        static func availableTitle(tagName: String) -> String {
            "PortBridge \(tagName) 업데이트가 있습니다"
        }
    }
}
