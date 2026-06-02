import AppKit
import Foundation

/// 임시 진단 로거 — 디버깅 종료 후 제거 예정.
/// 비샌드박스 앱이므로 /tmp에 직접 기록하여 외부에서 tail/read 가능.
enum PBDiag {
    private static let url = URL(fileURLWithPath: "/tmp/pb-diag.log")

    /// 앱 시작 시 호출해 로그 파일을 새로 시작(truncate).
    static func reset(_ msg: String) {
        try? "\(stamp()) \(msg)\n".data(using: .utf8)?.write(to: url)
    }

    static func log(_ msg: String) {
        guard let data = "\(stamp()) \(msg)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func stamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }

    /// 현재 NSApp.windows를 클래스 타입/타이틀/크기/가시성/key 상태와 함께 덤프.
    static func dumpWindows(_ tag: String) {
        let wins = NSApp.windows.map { w in
            "[\(type(of: w)) title='\(w.title)' \(Int(w.frame.width))x\(Int(w.frame.height)) vis=\(w.isVisible) key=\(w.isKeyWindow)]"
        }.joined(separator: " ")
        log("WINDOWS \(tag): count=\(NSApp.windows.count) \(wins)")
    }
}
