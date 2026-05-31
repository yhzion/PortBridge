import Foundation
@testable import PortBridge

/// Synchronous mock `FfiCommandRunner` for parity tests. Feeds canned command
/// results into the real core scan through the `scanPorts` FFI, so assertions
/// verify the actual core pipeline (classify/parse/dedup/filter).
final class MockFfiCommandRunner: FfiCommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    private let lock = NSLock()
    private var responses: [CommandResultDto] = []
    private(set) var calls: [Call] = []

    init(responses: [CommandResultDto] = []) {
        self.responses = responses
    }

    func run(executable: String, args: [String], timeout: TimeInterval) throws -> CommandResultDto {
        lock.lock()
        defer { lock.unlock() }
        calls.append(Call(executable: executable, args: args))
        guard !responses.isEmpty else {
            return CommandResultDto(exitCode: 0, stdout: "", stderr: "")
        }
        return responses.removeFirst()
    }
}
