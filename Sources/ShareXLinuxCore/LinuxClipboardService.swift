import Foundation

public struct LinuxClipboardPlan: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let contentType: String

    public init(executable: URL, arguments: [String], contentType: String) {
        self.executable = executable
        self.arguments = arguments
        self.contentType = contentType
    }
}

public final class LinuxClipboardService: @unchecked Sendable {
    public enum Kind: Sendable { case text, image }

    private let environment: LinuxDesktopEnvironment
    private let runner: LinuxProcessRunner

    public init(environment: LinuxDesktopEnvironment = .detect(), runner: LinuxProcessRunner = LinuxProcessRunner()) {
        self.environment = environment
        self.runner = runner
    }

    public static func plan(for environment: LinuxDesktopEnvironment, kind: Kind) throws -> LinuxClipboardPlan {
        switch environment.session {
        case .wayland:
            guard let executable = environment.executables["wl-copy"] else {
                throw LinuxSupportError.missingExecutable("wl-copy", installHint: "wl-clipboard")
            }
            return LinuxClipboardPlan(executable: executable, arguments: kind == .image ? ["--type", "image/png"] : [], contentType: kind == .image ? "image/png" : "text/plain")
        case .x11:
            guard let executable = environment.executables["xclip"] else {
                throw LinuxSupportError.missingExecutable("xclip", installHint: "xclip")
            }
            let arguments = kind == .image ? ["-selection", "clipboard", "-t", "image/png", "-i"] : ["-selection", "clipboard"]
            return LinuxClipboardPlan(executable: executable, arguments: arguments, contentType: kind == .image ? "image/png" : "text/plain")
        case .unknown:
            throw LinuxSupportError.unsupported("Clipboard integration requires an active Wayland or X11 session.")
        }
    }

    public func copyText(_ value: String) async throws {
        let plan = try Self.plan(for: environment, kind: .text)
        _ = try await runner.run(executable: plan.executable, arguments: plan.arguments, standardInput: Data(value.utf8))
    }

    public func copyImage(url: URL) async throws {
        let plan = try Self.plan(for: environment, kind: .image)
        _ = try await runner.run(executable: plan.executable, arguments: plan.arguments,
                                 standardInput: try Data(contentsOf: url))
    }
}
