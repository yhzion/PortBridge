import Foundation

/// 포워딩 항목 표시의 단일 캐노니컬 모델.
/// 메뉴바·메인 윈도우가 같은 필드·순서·라벨을 여기서 가져온다.
/// 색상·레이아웃은 각 표면이 자율적으로 렌더한다.
nonisolated struct ForwardingDisplay: Equatable {
    enum Status: Equatable { case active, starting, error, inactive }

    let status: Status
    let host: String
    let remotePort: Int
    let localPort: Int?
    let processName: String?
    let errorMessage: String?

    /// 불변식을 타입으로 강제하기 위해 private. 생성은 상태별 factory만 허용한다.
    /// (`localPort != nil ⇔ .active`, `errorMessage != nil ⇔ .error`)
    private init(
        status: Status,
        host: String,
        remotePort: Int,
        localPort: Int?,
        processName: String?,
        errorMessage: String?
    ) {
        self.status = status
        self.host = host
        self.remotePort = remotePort
        self.localPort = localPort
        self.processName = processName
        self.errorMessage = errorMessage
    }

    /// 확정 활성 포워딩. localPort가 non-optional이라 "active인데 화살표 없음"이 불가능.
    static func active(host: String, remotePort: Int, localPort: Int, processName: String?) -> ForwardingDisplay {
        ForwardingDisplay(
            status: .active,
            host: host,
            remotePort: remotePort,
            localPort: localPort,
            processName: processName,
            errorMessage: nil
        )
    }

    /// 연결 시도 중(로컬 포트는 아직 후보값이라 표시하지 않음).
    static func starting(host: String, remotePort: Int, processName: String?) -> ForwardingDisplay {
        ForwardingDisplay(
            status: .starting,
            host: host,
            remotePort: remotePort,
            localPort: nil,
            processName: processName,
            errorMessage: nil
        )
    }

    /// 포워딩 실패. message는 행의 info 툴팁 본문으로 보존된다.
    static func error(host: String, remotePort: Int, message: String, processName: String?) -> ForwardingDisplay {
        ForwardingDisplay(
            status: .error,
            host: host,
            remotePort: remotePort,
            localPort: nil,
            processName: processName,
            errorMessage: message
        )
    }

    /// 포워딩되지 않은 포트(또는 신뢰되지 않는/offline 상태로 보정된 항목).
    static func inactive(host: String, remotePort: Int, processName: String?) -> ForwardingDisplay {
        ForwardingDisplay(
            status: .inactive,
            host: host,
            remotePort: remotePort,
            localPort: nil,
            processName: processName,
            errorMessage: nil
        )
    }

    /// host를 제외한 꼬리. 메인 윈도우 행이 host(middle-truncation)와 분리 렌더할 때 쓴다.
    /// ":remotePort[ → :localPort][ · processName]"
    var suffix: String {
        var result = ":\(remotePort)"
        if status == .active, let localPort {
            result += " → :\(localPort)"
        }
        if let processName, !processName.isEmpty {
            result += " · \(processName)"
        }
        return result
    }

    /// 메뉴바·접근성 비교 기준이 되는 단일 문자열. 상태 dot은 포함하지 않는다.
    var line: String {
        host + suffix
    }

    /// 메뉴바 평문용 선행 표시.
    var statusDot: String {
        (status == .active || status == .starting) ? "●" : "○"
    }

    /// VoiceOver용 음성 표현. 시각 `line`과 필드·순서는 같되 `→`/`·` 대신 단어를 쓴다.
    var accessibilityText: String {
        let proc = if let processName, !processName.isEmpty {
            ", \(processName)"
        } else {
            ""
        }
        switch status {
        case .active:
            let local = localPort ?? 0
            return String(
                localized: "forwardingDisplay.a11y.active",
                defaultValue: "\(host) 포트 \(String(remotePort)), 로컬 \(String(local))으로 포워딩 중\(proc)"
            )
        case .starting:
            return String(
                localized: "forwardingDisplay.a11y.starting",
                defaultValue: "\(host) 포트 \(String(remotePort)), 포워딩 연결 중\(proc)"
            )
        case .error:
            return String(
                localized: "forwardingDisplay.a11y.error",
                defaultValue: "\(host) 포트 \(String(remotePort)), 포워딩 실패\(proc)"
            )
        case .inactive:
            return String(
                localized: "forwardingDisplay.a11y.inactive",
                defaultValue: "\(host) 포트 \(String(remotePort))\(proc)"
            )
        }
    }
}
