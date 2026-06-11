import Foundation

/// ssh stderr를 사용자 언어의 "원인 — 권장 조치" 한 줄로 요약한다.
///
/// 실패 원문은 진단 가치가 있어 버리지 않는다 — 행의 info 툴팁 등에 원문을 보존하고,
/// 인라인 표시는 이 요약을 쓴다. 미분류 패턴은 원문의 첫 비어있지 않은 줄로 폴백.
nonisolated enum SSHErrorSummarizer {
    private static let fallbackLimit = 120

    /// (패턴, 요약) 순서 유지 — 위에서부터 첫 매치가 이긴다.
    private static var rules: [(patterns: [String], summary: String)] {
        [
            (
                ["permission denied"],
                String(
                    localized: "sshError.permissionDenied",
                    defaultValue: "SSH 인증이 거부되었습니다 — 서버에 키가 등록됐는지 확인하세요"
                )
            ),
            (
                ["host key verification failed", "remote host identification has changed"],
                String(
                    localized: "sshError.hostKeyVerificationFailed",
                    defaultValue: "호스트 키 검증에 실패했습니다 — known_hosts의 키 변경 여부를 확인하세요"
                )
            ),
            (
                ["address already in use"],
                String(
                    localized: "sshError.addressInUse",
                    defaultValue: "로컬 포트가 이미 사용 중입니다 — 다른 로컬 포트로 연결하세요"
                )
            ),
            (
                ["connection refused"],
                String(
                    localized: "sshError.connectionRefused",
                    defaultValue: "연결이 거부되었습니다 — 원격 포트가 열려 있는지 확인하세요"
                )
            ),
            (
                ["timed out"],
                String(
                    localized: "sshError.timedOut",
                    defaultValue: "연결 시간이 초과되었습니다 — 서버 주소와 네트워크를 확인하세요"
                )
            ),
            (
                ["could not resolve hostname", "name or service not known"],
                String(
                    localized: "sshError.unresolvedHostname",
                    defaultValue: "호스트 이름을 찾을 수 없습니다 — 서버 주소를 확인하세요"
                )
            ),
            (
                ["no route to host"],
                String(
                    localized: "sshError.noRoute",
                    defaultValue: "서버에 도달할 수 없습니다 — 네트워크 경로를 확인하세요"
                )
            )
        ]
    }

    static func summary(for raw: String) -> String {
        let lowered = raw.lowercased()
        for rule in rules where rule.patterns.contains(where: lowered.contains) {
            return rule.summary
        }
        return fallback(for: raw)
    }

    private static func fallback(for raw: String) -> String {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine else {
            return String(localized: "sshError.unknown", defaultValue: "알 수 없는 오류")
        }
        guard firstLine.count > fallbackLimit else { return firstLine }
        return String(firstLine.prefix(fallbackLimit)) + "…"
    }
}
