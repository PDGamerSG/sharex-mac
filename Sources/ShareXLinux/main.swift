import Foundation
import Glibc
import ShareXLinuxCore

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
ShareX Linux — desktop screenshots, offline OCR, and image history
Usage: ShareXLinux [--action fullscreen|region|window|ocrRegion|history|settings|quit]
       ShareXLinux --autostart
"""

func launchDesktop(_ desktop: URL, _ executable: URL, _ arguments: [String]) throws -> Never {
    let python = "/usr/bin/python3"
    let values = [python, desktop.appendingPathComponent("sharex_ui.py").path, executable.path] + arguments
    var vector = values.map { strdup($0) } + [nil]
    defer { vector.forEach { free($0) } }
    _ = vector.withUnsafeMutableBufferPointer { execv(python, $0.baseAddress!) }
    throw LinuxSupportError.unsupported("Could not launch GTK. Install Python 3, python3-gi and gir1.2-gtk-3.0.")
}

do {
    if LinuxActionParser.parse(arguments: arguments) == .help { print(usage); exit(0) }
    let executable = URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe"))
    // SwiftPM puts the resource directory beside the executable in both development and installed builds.
    let desktop = executable.deletingLastPathComponent().appendingPathComponent("ShareXLinux_ShareXLinux.resources/Desktop")
    guard FileManager.default.fileExists(atPath: desktop.appendingPathComponent("sharex_ui.py").path) else {
        throw LinuxSupportError.unsupported("Desktop resources are missing beside ShareXLinux. Reinstall the Linux package.")
    }
    if arguments.first == "--backend" {
        let command = Backend(executable: executable, desktop: desktop)
        let operation = Task { try await command.run(Array(arguments.dropFirst())) }
        // The GTK picker can cancel a worker. Let Swift terminate its current child and clean its private staging directory.
        let signals = [SIGTERM, SIGINT].map { number in
            _ = signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { operation.cancel() }
            source.resume()
            return source
        }
        defer { signals.forEach { $0.cancel() } }
        try await operation.value
    } else {
        if case let .invalid(message) = LinuxActionParser.parse(arguments: arguments) {
            FileHandle.standardError.write(Data("\(message)\n\(usage)\n".utf8))
            exit(2)
        }
        try launchDesktop(desktop, executable, arguments)
    }
} catch is CancellationError {
    exit(130)
} catch LinuxProcessError.cancelled {
    exit(130)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
