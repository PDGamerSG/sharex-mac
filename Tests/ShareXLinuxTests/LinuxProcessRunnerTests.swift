import Foundation
import ShareXLinuxCore
import Testing

struct LinuxProcessRunnerTests {
    @Test("arguments containing spaces and shell syntax pass through literally")
    func arguments() async throws {
        let result = try await LinuxProcessRunner().run(name: "printf", arguments: ["%s", "a b $(literal)"])
        #expect(result.output == "a b $(literal)")
    }

    @Test("large clipboard input and output can exceed a pipe buffer")
    func largeInput() async throws {
        let data = Data(repeating: 42, count: 320_000)
        let result = try await LinuxProcessRunner().run(name: "cat", standardInput: data)
        #expect(result.standardOutput == data)
    }

    @Test("all executable calls propagate exit status and stderr")
    func nonZeroExit() async {
        await #expect(throws: LinuxProcessError.nonZeroExit(executable: "sh", code: 7, message: "bad")) {
            try await LinuxProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                               arguments: ["-c", "printf bad >&2; exit 7"])
        }
    }

    @Test("cancelling a running desktop helper terminates it promptly")
    func cancel() async throws {
        let task = Task { try await LinuxProcessRunner().run(name: "sleep", arguments: ["30"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
