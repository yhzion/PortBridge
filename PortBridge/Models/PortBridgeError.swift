import Foundation

enum PortBridgeError: LocalizedError, Equatable {
    case sshConfigNotFound
    case sshConfigUnreadable(String)
    case sshAuthFailed(host: String)
    case sshConnectTimeout(host: String)
    case remoteCommandNotFound
    case scanOutputUnparseable(String)
    case localPortInUse(Int)
    case forwardingDiedEarly(stderr: String)
    case tunnelCrashed(id: UUID, stderr: String)

    var errorDescription: String? {
        switch self {
        case .sshConfigNotFound:
            return "~/.ssh/config 파일을 찾을 수 없습니다."
        case .sshConfigUnreadable(let reason):
            return "ssh config을 읽지 못했습니다: \(reason)"
        case .sshAuthFailed(let host):
            return "\(host) SSH 인증 실패. 키 등록을 확인하세요."
        case .sshConnectTimeout(let host):
            return "\(host) 연결 타임아웃."
        case .remoteCommandNotFound:
            return "리모트에 ss/lsof 어느 쪽도 없습니다."
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
