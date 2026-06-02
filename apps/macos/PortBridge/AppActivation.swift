import AppKit
import Foundation

/// Accessory 모드(.accessory activation policy)에서 UI 표시를 위한 임시 활성화 관리.
///
/// macOS는 `.accessory` policy를 가진 앱의 `NSApp.activate()` 호출을 제한합니다.
/// 이 유틸리티는 UI 표시 전에 잠시 `.regular`로 전환하고, 완료 후 원래 policy로 복원합니다.
///
/// ## 사용 예시
/// ```swift
/// await AppActivation.withRegularPolicy {
///     NSApp.activate()
///     window.makeKeyAndOrderFront(nil)
/// }
/// ```
enum AppActivation {
    /// 현재 activation policy를 저장하고 `.regular`로 전환한 후 클로저를 실행하고 복원합니다.
    ///
    /// - Parameter work: 활성화 상태에서 실행할 작업
    /// - Returns: 클로저의 반환값
    @MainActor
    @discardableResult
    static func withRegularPolicy<T>(_ work: () throws -> T) rethrows -> T {
        let originalPolicy = NSApp.activationPolicy()

        // 이미 .regular이면 전환 불필요
        guard originalPolicy != .regular else {
            return try work()
        }

        // 임시로 .regular로 전환
        NSApp.setActivationPolicy(.regular)

        let result = try work()

        // macOS가 policy 전환과 UI 표시를 처리할 시간을 주기 위해
        // 다음 run loop cycle에서 원래 policy로 복원
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(originalPolicy)
        }

        return result
    }

    /// Accessory 모드에서도 안전하게 앱을 활성화합니다.
    ///
    /// - Parameter ignoringOtherApps: macOS 14 미만에서 다른 앱을 무시하고 활성화할지 여부
    @MainActor
    static func activate(ignoringOtherApps: Bool = true) {
        withRegularPolicy {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: ignoringOtherApps)
            }
        }
    }

    /// Accessory 모드에서도 안전하게 NSAlert를 모달로 실행합니다.
    ///
    /// - Parameter alert: 표시할 NSAlert
    /// - Returns: 사용자가 선택한 버튼 응답
    @MainActor
    @discardableResult
    static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        withRegularPolicy {
            activate()
            return alert.runModal()
        }
    }
}
