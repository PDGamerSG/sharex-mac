import Foundation

public enum LinuxDesktopSession: String, Sendable {
    case wayland, x11, unknown
}

public struct LinuxCommand: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum LinuxWindowSource: Equatable, Sendable {
    case sway(URL)
    case hyprland(URL)
}

public enum LinuxCaptureBackend: Equatable, Sendable {
    case grim(selector: URL?, windows: LinuxWindowSource?)
    case portal
    case maim
    case gnomeScreenshot
    case imageMagick(windowSelector: URL?)
}

public struct LinuxCapturePlan: Equatable, Sendable {
    public let session: LinuxDesktopSession
    public let command: LinuxCommand
    public let needsRegionSelection: Bool
    public let needsWindowSelection: Bool
    public let backend: LinuxCaptureBackend

    public init(session: LinuxDesktopSession, command: LinuxCommand,
                needsRegionSelection: Bool = false, needsWindowSelection: Bool = false,
                backend: LinuxCaptureBackend? = nil) {
        self.session = session
        self.command = command
        self.needsRegionSelection = needsRegionSelection
        self.needsWindowSelection = needsWindowSelection
        self.backend = backend ?? .portal
    }

    public var executable: URL { command.executable }
    public var arguments: [String] { command.arguments }
}

public struct LinuxDesktopEnvironment: Sendable, Equatable {
    public typealias WindowSource = LinuxWindowSource
    public enum Compositor: Sendable, Equatable {
        case sway, hyprland, portalDesktop, other
    }

    public let session: LinuxDesktopSession
    public let executables: [String: URL]
    public let compositor: Compositor

    public init(session: LinuxDesktopSession, executables: [String: URL], compositor: Compositor = .other) {
        self.session = session
        self.executables = executables
        self.compositor = compositor
    }

    public func has(_ executable: String) -> Bool { executables[executable] != nil }

    public static func detect(environment: [String: String] = ProcessInfo.processInfo.environment,
                              which: (String) -> URL? = LinuxProcessRunner.defaultExecutable) -> Self {
        let session: LinuxDesktopSession
        if !(environment["WAYLAND_DISPLAY"] ?? "").isEmpty {
            session = .wayland
        } else if !(environment["DISPLAY"] ?? "").isEmpty {
            session = .x11
        } else {
            session = .unknown
        }

        let desktopNames = ["XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION", "GDMSESSION"]
            .flatMap { (environment[$0] ?? "").lowercased().split(separator: ":").map(String.init) }
        let desktops = Set(desktopNames)
        let compositor: Compositor
        if desktops.contains("sway") || !(environment["SWAYSOCK"] ?? "").isEmpty {
            compositor = .sway
        } else if desktops.contains("hyprland") || !(environment["HYPRLAND_INSTANCE_SIGNATURE"] ?? "").isEmpty {
            compositor = .hyprland
        } else if !desktops.isDisjoint(with: ["gnome", "kde", "plasma", "cosmic"]) {
            compositor = .portalDesktop
        } else {
            compositor = .other
        }

        let names = ["grim", "slurp", "swaymsg", "hyprctl", "maim", "gnome-screenshot", "import",
                     "xdotool", "xrandr", "tesseract", "wl-copy", "xclip"]
        let executables = Dictionary(uniqueKeysWithValues: names.compactMap { name in which(name).map { (name, $0) } })
        return Self(session: session, executables: executables, compositor: compositor)
    }

    public func capturePlan(for mode: LinuxCaptureMode,
                            output: URL = URL(fileURLWithPath: "/tmp/sharex.png")) throws -> LinuxCapturePlan {
        switch session {
        case .wayland:
            if compositor != .portalDesktop, let grim = executables["grim"] {
                if mode == .fullscreen {
                    return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: [output.path]), backend: .grim(selector: nil, windows: nil))
                }
                guard let slurp = executables["slurp"] else {
                    return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: ["-g", "<geometry>", output.path]), needsRegionSelection: true, needsWindowSelection: mode == .window, backend: .portal)
                }
                if mode != .window {
                    return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: ["-g", "<geometry>", output.path]), needsRegionSelection: true, backend: .grim(selector: slurp, windows: nil))
                }
                if compositor == .sway, let swaymsg = executables["swaymsg"] {
                    return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: ["-g", "<geometry>", output.path]), needsRegionSelection: true, needsWindowSelection: true, backend: .grim(selector: slurp, windows: .sway(swaymsg)))
                }
                if compositor == .hyprland, let hyprctl = executables["hyprctl"] {
                    return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: ["-g", "<geometry>", output.path]), needsRegionSelection: true, needsWindowSelection: true, backend: .grim(selector: slurp, windows: .hyprland(hyprctl)))
                }
                return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: grim, arguments: ["-g", "<geometry>", output.path]), needsRegionSelection: true, needsWindowSelection: true, backend: .portal)
            }
            return LinuxCapturePlan(session: .wayland, command: LinuxCommand(executable: Self.portalURL, arguments: []), needsRegionSelection: mode != .fullscreen, needsWindowSelection: mode == .window, backend: .portal)

        case .x11:
            if let maim = executables["maim"] {
                return LinuxCapturePlan(session: .x11, command: LinuxCommand(executable: maim, arguments: mode == .fullscreen ? [output.path] : ["--select", "--tolerance", mode == .window ? "9999999" : "0", output.path]), needsRegionSelection: mode != .fullscreen, needsWindowSelection: mode == .window, backend: .maim)
            }
            if mode == .window {
                if let importer = executables["import"], let selector = executables["xdotool"] {
                    return LinuxCapturePlan(session: .x11, command: LinuxCommand(executable: importer, arguments: ["-window", "<window-id>", output.path]), needsWindowSelection: true, backend: .imageMagick(windowSelector: selector))
                }
                // gnome-screenshot's area mode must never be used for a window
                // action. Use a consented portal picker when no pointer-window
                // backend is available.
                return LinuxCapturePlan(session: .x11, command: LinuxCommand(executable: Self.portalURL, arguments: []), needsWindowSelection: true, backend: .portal)
            }
            if let gnome = executables["gnome-screenshot"] {
                let arguments = mode == .fullscreen ? ["-f", output.path] : ["-a", "-f", output.path]
                return LinuxCapturePlan(session: .x11, command: LinuxCommand(executable: gnome, arguments: arguments), needsRegionSelection: mode != .fullscreen, backend: .gnomeScreenshot)
            }
            if let importer = executables["import"] {
                return LinuxCapturePlan(session: .x11, command: LinuxCommand(executable: importer, arguments: mode == .fullscreen ? ["-window", "root", output.path] : [output.path]), needsRegionSelection: mode != .fullscreen, backend: .imageMagick(windowSelector: nil))
            }
            throw LinuxSupportError.missingExecutable("an X11 screenshot tool", installHint: "maim, gnome-screenshot or imagemagick")

        case .unknown:
            throw LinuxSupportError.unsupported("Start ShareX inside a Wayland or X11 desktop session to take a screenshot.")
        }
    }

    private static let portalURL = URL(fileURLWithPath: "/usr/bin/python3")
}
