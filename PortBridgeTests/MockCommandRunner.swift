import Foundation
@testable import PortBridge

final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    var calls: [Call] = []
    var responses: [CommandResult] = []
    var error: Error?

    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable, args: args))
        if let error = error { throw error }
        guard !responses.isEmpty else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return responses.removeFirst()
    }
}
