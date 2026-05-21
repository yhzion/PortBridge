// PortBridge/Scanning/PortScanner.swift
import Foundation

struct PortScanner {
    let runner: CommandRunner
    let sshExecutable: String = "/usr/bin/ssh"

    func scan(server: Server, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
        let remoteCommand = """
        if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
          echo PORTBRIDGE_TOOLS_MISSING >&2
          exit 127
        fi
        ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
        """
        let args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-p", "\(server.port)",
            server.sshTarget,
            remoteCommand
        ]

        let result = try await runner.run(sshExecutable, args: args, timeout: 15)

        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()

            // 1. 인증 실패 (최우선)
            if stderr.contains("permission denied") || stderr.contains("publickey") {
                throw PortBridgeError.sshAuthFailed(host: server.host)
            }

            // 2. 도달 불가 패턴 통합 (timeout 포함)
            let unreachablePatterns = [
                "connection timed out", "connect timeout",
                "no route to host",
                "connection refused",
                "could not resolve hostname", "name or service not known",
                "network is unreachable",
                "host is down",
            ]
            if unreachablePatterns.contains(where: { stderr.contains($0) }) {
                throw PortBridgeError.serverUnreachable(host: server.host, reason: result.stderr)
            }

            // 3. 도구 부재
            if result.exitCode == 127 || stderr.contains("portbridge_tools_missing") {
                throw PortBridgeError.remoteToolsMissing
            }
        }

        let first = result.stdout.components(separatedBy: .newlines).first ?? ""
        let parsed: [RemotePort]
        if first.uppercased().hasPrefix("LISTEN") || first.contains("State") {
            parsed = ScanOutputParser.parseSS(result.stdout)
        } else {
            parsed = ScanOutputParser.parseLsof(result.stdout)
        }

        let deduped = Self.deduplicateSamePort(parsed)
        return deduped
            .filter { range.contains($0.port) }
            .sorted { $0.port < $1.port }
    }

    private static func deduplicateSamePort(_ ports: [RemotePort]) -> [RemotePort] {
        let grouped = Dictionary(grouping: ports, by: \.port)
        return grouped.map { port, matches in
            RemotePort(
                port: port,
                address: representativeAddress(for: matches),
                processName: matches.first { port in
                    guard let name = port.processName else { return false }
                    return !name.isEmpty
                }?.processName
            )
        }
    }

    private static func representativeAddress(for ports: [RemotePort]) -> String {
        let addresses = ports.map(\.address)
        if addresses.contains("0.0.0.0") || addresses.contains("::") {
            return "0.0.0.0"
        }
        if addresses.contains("127.0.0.1") {
            return "127.0.0.1"
        }
        if addresses.contains("::1") {
            return "::1"
        }
        return addresses.sorted().first ?? ""
    }
}
