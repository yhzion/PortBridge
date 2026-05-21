import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)           // 유지 (Task 11에서 제거)
    case serverUnreachable(host: String, reason: String)  // NEW
    case remoteCommandNotFound                      // 유지 (Task 11에서 제거)
    case remoteToolsMissing                         // NEW
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: UUID, stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .sshConnectTimeout(let host):
            return "\(host) 연결 타임아웃."
        case .serverUnreachable(let host, _):
            return "\(host) 서버에 연결할 수 없습니다."
        case .remoteCommandNotFound:
            return "원격 서버에서 열린 포트 목록을 가져올 수 없습니다. (ss 또는 lsof 명령이 필요합니다)"
        case .remoteToolsMissing:
            return "원격 서버에 ss 또는 lsof가 필요합니다."
        case .scanOutputUnparseable(let preview):
            return "스캔 출력 파싱 실패: \(preview)"
        case .localPortInUse(let port):
            return "로컬 포트 \(port)이(가) 이미 사용 중입니다."
        case .forwardingDiedEarly(let stderr):
            return "포워딩이 즉시 종료되었습니다: \(stderr)"
        case .tunnelCrashed(_, let stderr):
            return "터널이 끊겼습니다: \(stderr)"
        }
    }
}
