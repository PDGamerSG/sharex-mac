import Foundation
import Glibc

public struct LinuxProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data = Data(), standardError: Data = Data()) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var output: String { String(decoding: standardOutput, as: UTF8.self) }
    public var errorOutput: String { String(decoding: standardError, as: UTF8.self) }
}

public enum LinuxProcessError: Error, LocalizedError, Equatable, Sendable {
    case missingExecutable(String)
    case nonZeroExit(executable: String, code: Int32, message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .missingExecutable(name): return "Install \(name) to use this action."
        case let .nonZeroExit(name, code, message):
            return message.isEmpty ? "\(name) exited with status \(code)." : "\(name): \(message)"
        case .cancelled: return "Capture cancelled."
        }
    }
}

public struct LinuxProcessRunner: Sendable {
    public typealias RunHandler = @Sendable (URL, [String], [String: String]?, Data?) async throws -> LinuxProcessResult
    private let resolve: @Sendable (String) -> URL?
    private let execute: RunHandler

    public init(executableResolver: @escaping @Sendable (String) -> URL? = Self.defaultExecutable,
                run: RunHandler? = nil) {
        resolve = executableResolver
        execute = run ?? Self.runProcess
    }

    public func which(_ name: String) -> URL? { resolve(name) }

    @discardableResult
    public func run(executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
                    standardInput: Data? = nil) async throws -> LinuxProcessResult {
        try Task.checkCancellation()
        let result = try await execute(executable, arguments, environment, standardInput)
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw LinuxProcessError.nonZeroExit(executable: executable.lastPathComponent, code: result.exitCode,
                                                message: result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    @discardableResult
    public func run(name: String, arguments: [String] = [], environment: [String: String]? = nil,
                    standardInput: Data? = nil) async throws -> LinuxProcessResult {
        guard let executable = resolve(name) else { throw LinuxProcessError.missingExecutable(name) }
        return try await run(executable: executable, arguments: arguments, environment: environment, standardInput: standardInput)
    }

    public static func defaultExecutable(_ name: String) -> URL? {
        for path in (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(path)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // Clipboard owners may fork and keep their stdio open. Anonymous files handle both
    // those descendants and large images without waiting for pipe capacity or EOF.
    private static func scratchFile() throws -> FileHandle {
        guard let file = tmpfile() else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { fclose(file) }
        let descriptor = fcntl(fileno(file), F_DUPFD_CLOEXEC, 3)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func runProcess(_ executable: URL, _ arguments: [String], _ environment: [String: String]?,
                                   _ input: Data?) async throws -> LinuxProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let output = try scratchFile()
        let errors = try scratchFile()
        process.standardOutput = output
        process.standardError = errors
        if let input {
            let file = try scratchFile()
            try file.write(contentsOf: input)
            try file.seek(toOffset: 0)
            process.standardInput = file
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let child = ChildProcess(process)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try child.start() }
                catch { continuation.resume(throwing: error) }
            }
        } onCancel: { child.cancel() }
        try Task.checkCancellation()
        try output.seek(toOffset: 0)
        try errors.seek(toOffset: 0)
        return try LinuxProcessResult(exitCode: status, standardOutput: output.readToEnd() ?? Data(),
                                      standardError: errors.readToEnd() ?? Data())
    }
}

private final class ChildProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var cancelled = false

    init(_ process: Process) { self.process = process }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) { [process] in
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
