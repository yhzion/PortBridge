// PortBridge/Scanning/PortScanner.swift
import Foundation

struct PortScanner {
    let runner: CommandRunner
    let sshExecutable: String = "/usr/bin/ssh"

    func scan(server: Server, range: ClosedRange<Int> = 1000...65535) async throws -> [RemotePort] {
        let remoteCommand = "ss -tlnpH 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"
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
            if stderr.contains("permission denied") || stderr.contains("publickey") {
                throw PortBridgeError.sshAuthFailed(host: server.host)
            }
            if stderr.contains("connection timed out") || stderr.contains("connect timeout") {
                throw PortBridgeError.sshConnectTimeout(host: server.host)
            }
            if result.stdout.isEmpty {
                throw PortBridgeError.remoteCommandNotFound
            }
        }

        let first = result.stdout.components(separatedBy: .newlines).first ?? ""
        let parsed: [RemotePort]
        if first.uppercased().hasPrefix("LISTEN") || first.contains("State") {
            parsed = ScanOutputParser.parseSS(result.stdout)
        } else {
            parsed = ScanOutputParser.parseLsof(result.stdout)
        }

        let deduped = Array(Set(parsed))
        return deduped
            .filter { range.contains($0.port) }
            .sorted { $0.port < $1.port }
    }
}
