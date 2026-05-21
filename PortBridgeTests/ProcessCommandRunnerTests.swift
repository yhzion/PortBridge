@testable import PortBridge
import XCTest

final class ProcessCommandRunnerTests: XCTestCase {
    func test_echo_returnsStdout() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run("/bin/echo", args: ["hello"], timeout: 2)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .newlines), "hello")
    }

    func test_falseExitsWithOne() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run("/usr/bin/false", args: [], timeout: 2)
        XCTAssertEqual(result.exitCode, 1)
    }
}
