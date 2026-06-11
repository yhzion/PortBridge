import Foundation
import UserNotifications

/// 시스템 알림 발송 경계 — AppViewModel이 UNUserNotificationCenter에 직접 묶이지 않게
/// 분리해 테스트에서 mock 주입을 가능하게 한다.
@MainActor
protocol UserNotifying {
    func post(title: String, body: String)
}

/// UNUserNotificationCenter 기반 기본 구현.
/// 권한은 첫 발송 시점에 요청한다 — 메뉴바 상주 앱에서 launch 시 권한 팝업으로
/// 사용자를 가로막지 않기 위함. 거부되면 조용히 발송을 생략한다(앱 동작엔 영향 없음).
@MainActor
final class UserNotificationCenterNotifier: UserNotifying {
    func post(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
