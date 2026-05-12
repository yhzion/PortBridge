// PortBridge/Tunneling/TunnelManager.swift
import Foundation
import Darwin

@MainActor
final class TunnelManager {
    /// Kills any ssh port-forward processes left over from a previous PortBridge
    /// run (force-quit, crash, Xcode stop, etc). Matches by the exact argv
    /// signature that `start(server:remotePort:localPort:)` emits below.
    ///
    /// Safe to call on every app launch — pgrep returns nothing when clean.
    nonisolated static func cleanupOrphanedTunnels() {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = [
            "-f",
            "/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o BatchMode=yes"
        ]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        let pids: [pid_t] = output
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        for pid in pids {
            _ = Darwin.kill(pid, SIGTERM)
        }
    }

    private(set) var active: [UUID: ActiveTunnel] = [:]
    weak var delegate: TunnelManagerDelegate?

    func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-p", "\(server.port)",
            "-L", "\(localPort):localhost:\(remotePort)",
            server.sshTarget
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        let stderrBuffer = StderrRingBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            stderrBuffer.append(data)
        }

        try process.run()

        try await Task.sleep(nanoseconds: 2_000_000_000)
        if !process.isRunning {
            let stderr = stderrBuffer.snapshot()
            throw PortBridgeError.forwardingDiedEarly(stderr: stderr)
        }

        let forwarding = Forwarding(
            serverId: server.id,
            serverDisplayName: server.displayName,
            remotePort: remotePort,
            localPort: localPort,
            state: .active
        )
        let tunnel = ActiveTunnel(process: process, forwarding: forwarding, stderr: stderrBuffer)
        active[forwarding.id] = tunnel

        let id = forwarding.id
        tunnel.monitorTask = Task { [weak self] in
            await Self.waitForExit(process)
            await self?.handleTunnelExit(id: id)
        }

        return forwarding
    }

    func stop(_ id: UUID) {
        guard let tunnel = active[id] else { return }
        tunnel.monitorTask?.cancel()
        tunnel.process.terminate()
        active.removeValue(forKey: id)
    }

    func shutdownAll() {
        for (_, tunnel) in active {
            tunnel.monitorTask?.cancel()
            tunnel.process.terminate()
        }
        for (_, tunnel) in active {
            tunnel.process.waitUntilExit()
        }
        active.removeAll()
    }

    private func handleTunnelExit(id: UUID) async {
        guard let tunnel = active[id] else { return }
        let stderr = tunnel.stderr.snapshot()
        active.removeValue(forKey: id)
        await delegate?.tunnelDidExit(id: id, stderr: stderr)
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
            if !process.isRunning {
                process.terminationHandler = nil
                cont.resume()
            }
        }
    }
}

protocol TunnelManagerDelegate: AnyObject {
    func tunnelDidExit(id: UUID, stderr: String) async
}

final class ActiveTunnel {
    let process: Process
    var forwarding: Forwarding
    let stderr: StderrRingBuffer
    var monitorTask: Task<Void, Never>?

    init(process: Process, forwarding: Forwarding, stderr: StderrRingBuffer) {
        self.process = process
        self.forwarding = forwarding
        self.stderr = stderr
    }
}

final class StderrRingBuffer: @unchecked Sendable {
    private let maxBytes = 4 * 1024
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer.removeFirst(buffer.count - maxBytes)
        }
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}
