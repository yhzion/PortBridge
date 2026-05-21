import Foundation
@testable import PortBridge

actor MockCommandRunner: CommandRunner {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    private(set) var calls: [Call] = []
    private var responses: [CommandResult] = []
    private var error: Error?

    func setResponses(_ responses: [CommandResult]) {
        self.responses = responses
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func run(_ executable: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable, args: args))
        if let error { throw error }
        guard !responses.isEmpty else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return responses.removeFirst()
    }
}
