import Foundation
import ShareXLinuxCore
import Testing

private actor CaptureCallLog {
    var calls: [(String, [String])] = []
    func append(_ executable: URL, _ arguments: [String]) { calls.append((executable.lastPathComponent, arguments)) }
    func values() -> [(String, [String])] { calls }
}

struct LinuxCaptureServiceTests {
    private let pngHeader = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
                                  0, 0, 0, 30, 0, 0, 0, 40, 8, 6, 0, 0, 0])

    @Test("Wayland region uses slurp geometry and grim without shell interpolation")
    func waylandRegion() async throws {
        let log = CaptureCallLog()
        let grim = URL(fileURLWithPath: "/usr/bin/grim")
        let slurp = URL(fileURLWithPath: "/usr/bin/slurp")
        let environment = LinuxDesktopEnvironment(session: .wayland, executables: ["grim": grim, "slurp": slurp])
        let runner = LinuxProcessRunner(run: { executable, arguments, _, _ in
            await log.append(executable, arguments)
            if executable == slurp { return LinuxProcessResult(exitCode: 0, standardOutput: Data("10,20 30x40\n".utf8)) }
            try Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
                      0, 0, 0, 30, 0, 0, 0, 40, 8, 6, 0, 0, 0]).write(to: URL(fileURLWithPath: arguments.last!))
            return LinuxProcessResult(exitCode: 0)
        })
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let image = try await LinuxCaptureService(environment: environment, runner: runner)
            .capture(mode: .region, settings: LinuxCaptureSettings(showCursor: true), temporaryDirectory: directory.url)
        #expect(image.width == 30)
        #expect(image.height == 40)
        let calls = await log.values()
        #expect(calls.count == 2)
        #expect(calls[0].0 == "slurp")
        #expect(calls[0].1 == ["-f", "%x,%y %wx%h"])
        #expect(calls[1].0 == "grim")
        #expect(Array(calls[1].1.dropLast()) == ["-c", "-g", "10,20 30x40"])
    }

    @Test("Wayland window capture never silently falls back to a freehand region")
    func waylandWindowRequiresPortalOrCompositorPicker() async {
        let environment = LinuxDesktopEnvironment(session: .wayland, executables: [
            "grim": URL(fileURLWithPath: "/usr/bin/grim"),
            "slurp": URL(fileURLWithPath: "/usr/bin/slurp")
        ])
        let directory = try? LinuxTestTemporaryDirectory()
        defer { directory?.remove() }
        await #expect(throws: LinuxSupportError.self) {
            try await LinuxCaptureService(environment: environment, runner: LinuxProcessRunner(run: { _, _, _, _ in
                LinuxProcessResult(exitCode: 0)
            })).capture(mode: .window, settings: LinuxCaptureSettings(), temporaryDirectory: directory!.url)
        }
    }

    @Test("X11 window mode passes the pointer-window selector to maim")
    func x11Window() async throws {
        let log = CaptureCallLog()
        let maim = URL(fileURLWithPath: "/usr/bin/maim")
        let environment = LinuxDesktopEnvironment(session: .x11, executables: ["maim": maim])
        let runner = LinuxProcessRunner(run: { executable, arguments, _, _ in
            await log.append(executable, arguments)
            try Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
                      0, 0, 0, 30, 0, 0, 0, 40, 8, 6, 0, 0, 0]).write(to: URL(fileURLWithPath: arguments.last!))
            return LinuxProcessResult(exitCode: 0)
        })
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        _ = try await LinuxCaptureService(environment: environment, runner: runner)
            .capture(mode: .window, settings: LinuxCaptureSettings(), temporaryDirectory: directory.url)
        let calls = await log.values()
        #expect(Array(calls[0].1.dropLast()) == ["--hidecursor", "--select", "--tolerance", "9999999"])
    }
}
