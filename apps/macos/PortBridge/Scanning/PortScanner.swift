// PortBridge/Scanning/PortScanner.swift
import Foundation

/// Thin adapter over the core scan via the `scanPorts` FFI. SSH arg
/// construction, stderr classification, parsing, dedup, range filtering all
/// live in core — this type only marshals types and hops the sync FFI call
/// onto a background thread.
nonisolated struct PortScanner {
    let runner: FfiCommandRunner

    func scan(server: Server) async throws -> [RemotePort] {
        guard let port = UInt16(exactly: server.port) else {
            throw PortBridgeError.serverUnreachable(
                host: server.host,
                reason: "포트 번호가 범위를 벗어났습니다: \(server.port)"
            )
        }

        let dto = ServerDto(
            id: server.id.uuidString,
            name: server.name,
            user: server.user,
            host: server.host,
            port: port
        )

        nonisolated(unsafe) let runner = runner
        nonisolated(unsafe) let serverDto = dto

        // 생성 바인딩 `scanPorts`는 default MainActor 격리(SWIFT_DEFAULT_ACTOR_ISOLATION)를
        // 받아 @MainActor다. async 컨텍스트(예: Task.detached)에서 호출하면 런타임이
        // 메인 액터로 hop해 블로킹 SSH가 메인 스레드를 얼린다(무지개 커서). 동기 GCD
        // 클로저에서 호출하면 Swift 5 모드에서 격리 위반이 warning일 뿐 hop이 생기지
        // 않아 실제 백그라운드 스레드에서 돈다. 근본 해결은 생성 바인딩을 default-isolation
        // 미적용 모듈로 분리하는 것(그때까지 Task.detached로 되돌리지 말 것).
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try scanPorts(runner: runner, server: serverDto)
                    continuation.resume(returning: result.map {
                        RemotePort(port: Int($0.port), address: $0.address, processName: $0.processName)
                    })
                } catch let error as PortBridgeFfiError {
                    continuation.resume(throwing: Self.map(error))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func map(_ error: PortBridgeFfiError) -> PortBridgeError {
        switch error {
        case .SshAuthFailed(let host):
            return .sshAuthFailed(host: host)
        case .ServerUnreachable(let host, let reason):
            return .serverUnreachable(host: host, reason: reason)
        case .RemoteToolsMissing:
            return .remoteToolsMissing
        default:
            // scan 경로는 scan 분류 3-variant만 방출한다. ssh-config(resolve_host)·
            // version 등 다른 경로 전용 FFI 에러는 scan에 도달하지 않는다. default로
            // 두어 FFI enum 확장(#85의 SshConfig* 등)에 robust하게 한다 — 도달 불가.
            preconditionFailure("scan never emits non-scan FFI errors: \(error)")
        }
    }
}
