import Foundation

/// Reports how the native GTK desktop adapter should expose global shortcuts.
///
/// Registrations themselves are owned by `Desktop/shortcuts.py`, which uses
/// Keybinder3 on X11 and `org.freedesktop.portal.GlobalShortcuts` on Wayland.
/// This value type remains in the core target so callers can show a useful
/// status without linking GTK or starting a helper process.
public enum LinuxHotkeyStatus: Equatable, Sendable {
    case registered
    case portalAvailable
    case missingKeybinder
    /// Legacy status retained for source compatibility. Native portal support
    /// is reported as `portalAvailable` by the new adapter.
    case waylandGuidance
    /// Legacy xbindkeys status retained for older callers.
    case missingXBindKeys
    case unsupportedSession
}

@available(*, deprecated, message: "Use the native Desktop/shortcuts.py adapter from GTK.")
public final class LinuxHotkeyRegistrar: @unchecked Sendable {
    private let environment: LinuxDesktopEnvironment

    public init(environment: LinuxDesktopEnvironment = .detect()) {
        self.environment = environment
    }

    /// Returns the adapter capability without invoking a shell or helper.
    public static func status(for environment: LinuxDesktopEnvironment) -> LinuxHotkeyStatus {
        switch environment.session {
        case .wayland:
            return .portalAvailable
        case .x11:
            return .registered
        case .unknown:
            return .unsupportedSession
        }
    }

    /// Compatibility entry point for older controller code. GTK owns the
    /// actual callback registration and applies these values through Python.
    @discardableResult
    public func register(_ bindings: [String: [LinuxHotkeyBinding]], executable: URL) throws -> LinuxHotkeyStatus {
        _ = bindings
        _ = executable
        return Self.status(for: environment)
    }

    /// Returns the legacy xbindkeys text representation for callers that
    /// still preview or persist a configuration. The running Linux app uses
    /// the GTK adapter instead of launching xbindkeys.
    public static func configuration(for bindings: [String: [LinuxHotkeyBinding]], executable: URL) -> String {
        let entries = bindings.keys.sorted().flatMap { action in
            (bindings[action] ?? []).map { binding in
                let accelerator = (binding.modifiers + [binding.key]).joined(separator: " + ")
                let command = "\(shellQuote(executable.path)) --action \(shellQuote(action))"
                return "\"\(command)\"\n  \(accelerator)"
            }
        }
        return entries.joined(separator: "\n\n") + (entries.isEmpty ? "" : "\n")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }

    public func stop() {}
}
