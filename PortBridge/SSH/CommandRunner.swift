import Foundation

struct CommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner: Sendable {
    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult
}

enum CommandError: Error, Equatable {
    case timedOut
    case launchFailed(String)
}
