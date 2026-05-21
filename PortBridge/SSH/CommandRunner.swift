import Foundation

nonisolated struct CommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

nonisolated protocol CommandRunner: Sendable {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult
}

nonisolated enum CommandError: Error, Equatable {
    case timedOut
    case launchFailed(String)
}
