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

        return try await Task.detached {
            do {
                let result = try scanPorts(runner: runner, server: serverDto)
                return result.map {
                    RemotePort(port: Int($0.port), address: $0.address, processName: $0.processName)
                }
            } catch let error as PortBridgeFfiError {
                throw Self.map(error)
            }
        }.value
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
