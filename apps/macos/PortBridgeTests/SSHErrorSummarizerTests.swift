@testable import PortBridge
import XCTest

final class SSHErrorSummarizerTests: XCTestCase {
    // MARK: - 알려진 ssh stderr 패턴 → 한국어 원인+조치

    func test_summary_permissionDenied() {
        let raw = "user@10.0.0.1: Permission denied (publickey)."
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "SSH 인증이 거부되었습니다 — 서버에 키가 등록됐는지 확인하세요"
        )
    }

    func test_summary_hostKeyVerificationFailed() {
        let raw = "Host key verification failed."
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "호스트 키 검증에 실패했습니다 — known_hosts의 키 변경 여부를 확인하세요"
        )
    }

    func test_summary_remoteHostIdentificationChanged_mapsToHostKey() {
        let raw = "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "호스트 키 검증에 실패했습니다 — known_hosts의 키 변경 여부를 확인하세요"
        )
    }

    func test_summary_addressAlreadyInUse() {
        let raw = "bind [127.0.0.1]:8080: Address already in use"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "로컬 포트가 이미 사용 중입니다 — 다른 로컬 포트로 연결하세요"
        )
    }

    func test_summary_connectionRefused() {
        let raw = "connect_to localhost port 5173: failed.\nchannel 1: open failed: connect failed: Connection refused"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "연결이 거부되었습니다 — 원격 포트가 열려 있는지 확인하세요"
        )
    }

    func test_summary_timedOut() {
        let raw = "ssh: connect to host 10.0.0.9 port 22: Operation timed out"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "연결 시간이 초과되었습니다 — 서버 주소와 네트워크를 확인하세요"
        )
    }

    func test_summary_couldNotResolveHostname() {
        let raw = "ssh: Could not resolve hostname my-server: Name or service not known"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "호스트 이름을 찾을 수 없습니다 — 서버 주소를 확인하세요"
        )
    }

    func test_summary_noRouteToHost() {
        let raw = "ssh: connect to host 192.168.9.9 port 22: No route to host"
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: raw),
            "서버에 도달할 수 없습니다 — 네트워크 경로를 확인하세요"
        )
    }

    func test_summary_isCaseInsensitive() {
        XCTAssertEqual(
            SSHErrorSummarizer.summary(for: "PERMISSION DENIED"),
            "SSH 인증이 거부되었습니다 — 서버에 키가 등록됐는지 확인하세요"
        )
    }

    // MARK: - isHostKeyFailure (보안 관련 — 오프라인으로 위장되면 안 됨)

    func test_isHostKeyFailure_verificationFailed() {
        XCTAssertTrue(SSHErrorSummarizer.isHostKeyFailure("Host key verification failed."))
    }

    func test_isHostKeyFailure_identificationChanged() {
        XCTAssertTrue(
            SSHErrorSummarizer.isHostKeyFailure("@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@")
        )
    }

    func test_isHostKeyFailure_falseForOrdinaryNetworkError() {
        XCTAssertFalse(SSHErrorSummarizer.isHostKeyFailure("Connection refused"))
        XCTAssertFalse(SSHErrorSummarizer.isHostKeyFailure("Connection timed out"))
    }

    // MARK: - 폴백

    func test_summary_unknownPattern_fallsBackToFirstNonEmptyLine() {
        let raw = "\n\n  some unusual ssh failure  \nsecond line"
        XCTAssertEqual(SSHErrorSummarizer.summary(for: raw), "some unusual ssh failure")
    }

    func test_summary_unknownPattern_truncatesLongLine() {
        let raw = String(repeating: "x", count: 300)
        let summary = SSHErrorSummarizer.summary(for: raw)
        XCTAssertEqual(summary.count, 121) // 120자 + 말줄임표
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    func test_summary_emptyInput_returnsGenericMessage() {
        XCTAssertEqual(SSHErrorSummarizer.summary(for: "  \n "), "알 수 없는 오류")
    }
}
