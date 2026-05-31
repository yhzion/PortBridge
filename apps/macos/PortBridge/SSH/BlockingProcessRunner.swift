import Foundation

/// Synchronous, blocking `FfiCommandRunner` injected into the core scan via
/// the `scanPorts` FFI. Core calls `run` on a background thread (PortScanner
/// dispatches the whole FFI call off the main actor), so blocking here is safe.
final class BlockingProcessRunner: FfiCommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], timeout: TimeInterval) throws -> CommandResultDto {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timedOut = NSLock()
        var didTimeout = false

        let watchdog = DispatchWorkItem {
            timedOut.lock()
            didTimeout = true
            timedOut.unlock()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        do {
            try process.run()
        } catch {
            watchdog.cancel()
            throw CommandErrorDto.LaunchFailed(reason: error.localizedDescription)
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        watchdog.cancel()

        timedOut.lock()
        let wasTimeout = didTimeout
        timedOut.unlock()
        if wasTimeout {
            throw CommandErrorDto.TimedOut
        }

        return CommandResultDto(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
