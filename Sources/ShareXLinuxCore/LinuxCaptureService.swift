import Foundation

public final class LinuxCaptureService: Sendable {
    private let environment: LinuxDesktopEnvironment
    private let runner: LinuxProcessRunner
    private let portalHelper: URL?

    public init(environment: LinuxDesktopEnvironment = .detect(), runner: LinuxProcessRunner = LinuxProcessRunner(),
                portalHelper: URL? = nil) {
        self.environment = environment
        self.runner = runner
        self.portalHelper = portalHelper
    }

    public func capture(mode: LinuxCaptureMode, settings: LinuxCaptureSettings,
                        temporaryDirectory: URL = FileManager.default.temporaryDirectory) async throws -> LinuxCapturedImage {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let output = temporaryDirectory.appendingPathComponent("ShareX-\(UUID().uuidString).png")
        let plan = try environment.capturePlan(for: mode, output: output)
        var window: DesktopWindow?
        var displayCount: Int?
        do {
            switch plan.backend {
            case let .grim(selector, source):
                let grim = plan.executable
                do {
                    window = try await captureGrim(grim, selector: selector, source: source, cursor: settings.showCursor, output: output)
                } catch let LinuxProcessError.nonZeroExit(name, _, message)
                    where (name == "grim" || name == "slurp") && message.lowercased().contains("doesn't support") {
                    displayCount = try await capturePortal(mode: mode, cursor: settings.showCursor, output: output)
                }
            case .portal:
                displayCount = try await capturePortal(mode: mode, cursor: settings.showCursor, output: output)
            case .maim:
                let maim = plan.executable
                var arguments = settings.showCursor ? [] : ["--hidecursor"]
                // slop defines zero tolerance as drag-only, and 9999999 as window-only.
                if mode != .fullscreen { arguments += ["--select", "--tolerance", mode == .window ? "9999999" : "0"] }
                try await runPicker(maim, arguments + [output.path])
            case .gnomeScreenshot:
                let gnome = plan.executable
                var arguments = mode == .fullscreen ? [] : ["-a"]
                if settings.showCursor { arguments.append("-p") }
                try await runPicker(gnome, arguments + ["-f", output.path])
                // gnome-screenshot exits successfully on Escape without writing the file.
                if mode != .fullscreen && !FileManager.default.fileExists(atPath: output.path) { throw CancellationError() }
            case let .imageMagick(windowSelector: selector):
                let importer = plan.executable
                var arguments = ["-silent"]
                if let selector {
                    let id = try await select(selector, ["selectwindow"])
                    guard let numericID = UInt64(id) else { throw LinuxSupportError.invalidOutput("The X11 window picker returned an invalid window ID.") }
                    guard numericID > 0 else { throw CancellationError() }
                    arguments += ["-window", id]
                    let title = try? await runner.run(executable: selector, arguments: ["getwindowname", id]).output
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    window = DesktopWindow(geometry: "", title: title, application: nil)
                } else if mode == .fullscreen {
                    arguments += ["-window", "root"]
                }
                try await runPicker(importer, arguments + [output.path])
                if mode != .fullscreen && !FileManager.default.fileExists(atPath: output.path) {
                    throw CancellationError()
                }
            }
            if mode == .fullscreen && displayCount == nil { displayCount = await activeDisplayCount() }
            try Task.checkCancellation()
            let size = try LinuxPNGMetadata.read(url: output)
            return LinuxCapturedImage(path: output, width: size.width, height: size.height,
                                      windowTitle: window?.title, applicationName: window?.application, displayCount: displayCount)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private func captureGrim(_ grim: URL, selector: URL?, source: LinuxWindowSource?,
                             cursor: Bool, output: URL) async throws -> DesktopWindow? {
        var arguments = cursor ? ["-c"] : []
        var window: DesktopWindow?
        if let selector {
            let geometry: String
            if let source {
                let candidates = try await windows(from: source)
                guard !candidates.isEmpty else { throw LinuxSupportError.unsupported("There are no visible windows to capture.") }
                // Restrict slurp to these compositor rectangles. Send only generated IDs as labels.
                let rectangles = candidates.enumerated().map { "\($0.element.geometry) \($0.offset)\n" }.joined()
                let label = try await select(selector, ["-r", "-f", "%l"], input: Data(rectangles.utf8))
                guard let index = Int(label), candidates.indices.contains(index) else {
                    throw LinuxSupportError.invalidOutput("The window picker returned an unknown window.")
                }
                window = candidates[index]
                geometry = candidates[index].geometry
            } else {
                geometry = try await select(selector, ["-f", "%x,%y %wx%h"])
                guard geometry.range(of: #"^-?[0-9]+,-?[0-9]+ [1-9][0-9]*x[1-9][0-9]*$"#,
                                     options: .regularExpression) != nil else {
                    throw LinuxSupportError.invalidOutput("The region picker returned an invalid rectangle.")
                }
            }
            arguments += ["-g", geometry]
        }
        _ = try await runner.run(executable: grim, arguments: arguments + [output.path])
        return window
    }

    private func capturePortal(mode: LinuxCaptureMode, cursor: Bool, output: URL) async throws -> Int? {
        guard let portalHelper else {
            throw LinuxSupportError.unsupported("The ShareX desktop capture helper is missing. Reinstall the ShareX Linux desktop bundle.")
        }
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        do {
            let arguments = [portalHelper.path, mode.rawValue, output.path] + (cursor ? ["--cursor"] : [])
            let result = try await runner.run(executable: python, arguments: arguments)
            return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch LinuxProcessError.nonZeroExit(_, 130, _) {
            throw CancellationError()
        }
    }

    @discardableResult
    private func runPicker(_ executable: URL, _ arguments: [String], input: Data? = nil) async throws -> LinuxProcessResult {
        do {
            return try await runner.run(executable: executable, arguments: arguments, standardInput: input)
        } catch let LinuxProcessError.nonZeroExit(_, code, message)
            where code == 1 && (message.localizedCaseInsensitiveContains("cancelled") || message.localizedCaseInsensitiveContains("canceled")) {
            throw CancellationError()
        }
    }

    private func select(_ executable: URL, _ arguments: [String], input: Data? = nil) async throws -> String {
        let result = try await runPicker(executable, arguments, input: input)
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CancellationError() }
        return value
    }

    private func windows(from source: LinuxWindowSource) async throws -> [DesktopWindow] {
        let decoder = JSONDecoder()
        switch source {
        case let .sway(tool):
            let workspaces = try await runner.run(executable: tool, arguments: ["-r", "-t", "get_workspaces"])
            let focused = try decoder.decode([SwayWorkspace].self, from: workspaces.standardOutput)
                .first(where: { $0.focused })?.name
            let tree = try await runner.run(executable: tool, arguments: ["-r", "-t", "get_tree"])
            return try decoder.decode(SwayNode.self, from: tree.standardOutput).windows(currentWorkspace: focused)
        case let .hyprland(tool):
            let monitors = try await runner.run(executable: tool, arguments: ["-j", "monitors"])
            let visible = Set(try decoder.decode([HyprMonitor].self, from: monitors.standardOutput).flatMap(\.visibleWorkspaces))
            let clients = try await runner.run(executable: tool, arguments: ["-j", "clients"])
            return try decoder.decode([HyprClient].self, from: clients.standardOutput).compactMap { $0.window(on: visible) }
        }
    }

    private func activeDisplayCount() async -> Int? {
        if environment.session == .x11, let xrandr = environment.executables["xrandr"] {
            let result = try? await runner.run(executable: xrandr, arguments: ["--listactivemonitors"])
            let firstLine = result?.output.split(separator: "\n").first
            return firstLine?.split(separator: " ").last.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        }
        if environment.compositor == .sway, let tool = environment.executables["swaymsg"],
           let result = try? await runner.run(executable: tool, arguments: ["-r", "-t", "get_outputs"]),
           let outputs = try? JSONDecoder().decode([SwayOutput].self, from: result.standardOutput) {
            return outputs.filter(\.active).count
        }
        if environment.compositor == .hyprland, let tool = environment.executables["hyprctl"],
           let result = try? await runner.run(executable: tool, arguments: ["-j", "monitors"]),
           let monitors = try? JSONDecoder().decode([HyprMonitor].self, from: result.standardOutput) {
            return monitors.count
        }
        return nil
    }
}

private struct DesktopWindow {
    let geometry: String
    let title: String?
    let application: String?
}

private struct SwayOutput: Decodable {
    let active: Bool
}

private struct SwayWorkspace: Decodable {
    let name: String
    let focused: Bool
}

private struct SwayNode: Decodable {
    struct Rect: Decodable { let x, y, width, height: Int }
    struct X11Properties: Decodable { let `class`: String? }
    let type: String
    let name, app_id, current_workspace: String?
    let pid, window: Int?
    let visible: Bool?
    let rect: Rect?
    let window_properties: X11Properties?
    let nodes, floating_nodes: [SwayNode]?

    func windows(currentWorkspace: String? = nil) -> [DesktopWindow] {
        if type == "workspace" && (name == "__i3_scratch" || (currentWorkspace != nil && currentWorkspace != name)) { return [] }
        if type == "con" || type == "floating_con", visible != false,
           app_id != nil || window != nil || pid != nil, let rect, rect.width > 0, rect.height > 0 {
            return [DesktopWindow(geometry: "\(rect.x),\(rect.y) \(rect.width)x\(rect.height)", title: name,
                                  application: app_id ?? window_properties?.class)]
        }
        let workspace = current_workspace ?? currentWorkspace
        return ((nodes ?? []) + (floating_nodes ?? [])).flatMap { $0.windows(currentWorkspace: workspace) }
    }
}

private struct HyprWorkspace: Decodable { let id: Int }

private struct HyprMonitor: Decodable {
    let activeWorkspace: HyprWorkspace
    let specialWorkspace: HyprWorkspace?

    var visibleWorkspaces: [Int] {
        [activeWorkspace.id] + [specialWorkspace?.id].compactMap { $0 }.filter { $0 != 0 }
    }
}

private struct HyprClient: Decodable {
    let mapped, hidden, pinned: Bool?
    let workspace: HyprWorkspace
    let at, size: [Int]
    let title, `class`: String?

    func window(on visible: Set<Int>) -> DesktopWindow? {
        guard mapped != false, hidden != true, pinned == true || visible.contains(workspace.id),
              at.count == 2, size.count == 2, size[0] > 0, size[1] > 0 else { return nil }
        return DesktopWindow(geometry: "\(at[0]),\(at[1]) \(size[0])x\(size[1])", title: title, application: `class`)
    }
}
