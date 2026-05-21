import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case serverUnreachable(host: String, reason: String)
    case remoteToolsMissing
    case forwardingDiedEarly(stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .serverUnreachable(let host, _):
            return "\(host) 서버에 연결할 수 없습니다."
        case .remoteToolsMissing:
            return "원격 서버에 ss 또는 lsof가 필요합니다."
        case .forwardingDiedEarly(let stderr):
            return "포워딩이 즉시 종료되었습니다: \(stderr)"
        }
    }
}
