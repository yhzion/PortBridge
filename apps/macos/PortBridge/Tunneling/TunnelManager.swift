// PortBridge/Tunneling/TunnelManager.swift
import Darwin
import Foundation

@MainActor
protocol TunnelManaging: AnyObject {
    var delegate: TunnelManagerDelegate? { get set }
    func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding
    func stop(_ id: UUID)
    /// SIGTERM 후 프로세스가 실제로 종료될 때까지 대기. 같은 localport로 즉시 재시작할 때
    /// "Address already in use" 충돌을 피하기 위해 사용 (자동 재접속 경로 등).
    func stopAndWait(_ id: UUID) async
    func shutdownAll()
}

@MainActor
final class TunnelManager: TunnelManaging {
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

    /// 터널 ssh 인자. Rust core(`crates/portbridge-core/src/tunnel.rs`)와 동일해야 한다.
    /// `ConnectTimeout=10`이 빠지면 도달 불가 호스트가 TCP connect에서 매달려 2초 start
    /// grace를 통과하고 가짜 `.active`로 보고된다. `ConnectTimeout`은 `BatchMode=yes` 뒤에
    /// 두어 `cleanupOrphanedTunnels()`의 pgrep prefix가 신·구 프로세스를 모두 매칭하게 유지한다.
    static func tunnelArguments(serverPort: Int, localPort: Int, remotePort: Int, sshTarget: String) -> [String] {
        [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-p", "\(serverPort)",
            "-L", "\(localPort):localhost:\(remotePort)",
            sshTarget
        ]
    }

    func start(server: Server, remotePort: Int, localPort: Int) async throws -> Forwarding {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.tunnelArguments(
            serverPort: server.port,
            localPort: localPort,
            remotePort: remotePort,
            sshTarget: server.sshTarget
        )

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        let stderrBuffer = StderrRingBuffer()
        let (stderrStream, stderrContinuation) = AsyncStream<Data>.makeStream()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            stderrContinuation.yield(data)
        }
        let stderrConsumer = Task {
            for await chunk in stderrStream {
                await stderrBuffer.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stderrContinuation.finish()
            await stderrConsumer.value
            throw error
        }

        let exitedEarly = await Self.raceExitVsGrace(
            process: process,
            graceNanoseconds: 2_000_000_000
        )
        if exitedEarly {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stderrContinuation.finish()
            await stderrConsumer.value
            let stderr = await stderrBuffer.snapshot()
            throw PortBridgeError.forwardingDiedEarly(stderr: stderr)
        }

        let forwarding = Forwarding(
            serverId: server.id,
            remotePort: remotePort,
            localPort: localPort,
            state: .active
        )
        let tunnel = ActiveTunnel(
            id: forwarding.id,
            process: process,
            stderr: stderrBuffer,
            stderrContinuation: stderrContinuation,
            stderrConsumer: stderrConsumer
        )
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
        (tunnel.process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        tunnel.monitorTask?.cancel()
        tunnel.process.terminate()
        tunnel.stderrContinuation.finish()
        active.removeValue(forKey: id)
    }

    func stopAndWait(_ id: UUID) async {
        guard let tunnel = active[id] else { return }
        (tunnel.process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        tunnel.monitorTask?.cancel()
        let process = tunnel.process
        process.terminate()
        tunnel.stderrContinuation.finish()
        active.removeValue(forKey: id)
        await Self.waitForExit(process)
    }

    func shutdownAll() {
        for (_, tunnel) in active {
            (tunnel.process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            tunnel.monitorTask?.cancel()
            tunnel.process.terminate()
            tunnel.stderrContinuation.finish()
        }
        for (_, tunnel) in active {
            tunnel.process.waitUntilExit()
        }
        active.removeAll()
    }

    private func handleTunnelExit(id: UUID) async {
        guard let tunnel = active.removeValue(forKey: id) else { return }
        (tunnel.process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        tunnel.stderrContinuation.finish()
        await tunnel.stderrConsumer.value
        let stderr = await tunnel.stderr.snapshot()
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

    /// 시작 직후 SSH가 빨리 죽는 케이스(인증 실패, 포트 충돌)는 즉시 보고하고,
    /// 그렇지 않으면 grace window까지만 기다린 뒤 정상 시작으로 간주합니다.
    /// returns: true = grace 안에 종료(실패), false = grace 통과(성공)
    private static func raceExitVsGrace(
        process: Process,
        graceNanoseconds: UInt64
    ) async -> Bool {
        // terminationHandler는 임의 스레드에서, sleep 분기는 우리 Task에서 발화 가능.
        // 첫 호출만 cont.resume()을 통과시키는 one-shot 가드.
        final class OneShot: @unchecked Sendable {
            let lock = NSLock()
            nonisolated(unsafe) var fired = false
            nonisolated func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if fired { return false }
                fired = true
                return true
            }
        }
        let gate = OneShot()
        let exited: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            process.terminationHandler = { _ in
                if gate.claim() { cont.resume(returning: true) }
            }
            if !process.isRunning, gate.claim() {
                cont.resume(returning: true)
            }
            Task {
                try? await Task.sleep(nanoseconds: graceNanoseconds)
                if gate.claim() { cont.resume(returning: false) }
            }
        }
        // 호출자(monitorTask)가 자기 핸들러를 설치할 수 있도록 떼어둡니다.
        process.terminationHandler = nil
        return exited
    }
}

protocol TunnelManagerDelegate: AnyObject {
    func tunnelDidExit(id: UUID, stderr: String) async
}

final class ActiveTunnel {
    let id: UUID
    let process: Process
    let stderr: StderrRingBuffer
    let stderrContinuation: AsyncStream<Data>.Continuation
    let stderrConsumer: Task<Void, Never>
    var monitorTask: Task<Void, Never>?

    init(
        id: UUID,
        process: Process,
        stderr: StderrRingBuffer,
        stderrContinuation: AsyncStream<Data>.Continuation,
        stderrConsumer: Task<Void, Never>
    ) {
        self.id = id
        self.process = process
        self.stderr = stderr
        self.stderrContinuation = stderrContinuation
        self.stderrConsumer = stderrConsumer
    }
}

actor StderrRingBuffer {
    private let maxBytes = 4 * 1024
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer.removeFirst(buffer.count - maxBytes)
        }
    }

    func snapshot() -> String {
        String(data: buffer, encoding: .utf8) ?? ""
    }
}
