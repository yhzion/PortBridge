import Foundation

final class ProcessCommandRunner: CommandRunner, @unchecked Sendable {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withThrowingTaskGroup(of: CommandResult?.self) { group in
            group.addTask {
                try process.run()

                async let stdoutData = Self.readAll(stdoutPipe.fileHandleForReading)
                async let stderrData = Self.readAll(stderrPipe.fileHandleForReading)

                process.waitUntilExit()
                let so = await stdoutData
                let se = await stderrData
                return CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: so, encoding: .utf8) ?? "",
                    stderr: String(data: se, encoding: .utf8) ?? ""
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
                return nil
            }

            defer { group.cancelAll() }
            for try await result in group {
                if let result = result { return result }
                throw CommandError.timedOut
            }
            throw CommandError.launchFailed("no result")
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached {
            (try? handle.readToEnd()) ?? Data()
        }.value
    }
}
