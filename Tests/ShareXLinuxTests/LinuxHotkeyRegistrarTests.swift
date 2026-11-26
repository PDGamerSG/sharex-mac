import Foundation
import ShareXLinuxCore
import Testing

struct LinuxHotkeyRegistrarTests {
    @Test("X11 uses the native GTK adapter")
    func x11Status() {
        let status = LinuxHotkeyRegistrar.status(for: LinuxDesktopEnvironment(session: .x11, executables: [:]))
        #expect(status == .registered)
    }

    @Test("Wayland advertises the GlobalShortcuts portal path")
    func waylandStatus() {
        let status = LinuxHotkeyRegistrar.status(for: LinuxDesktopEnvironment(session: .wayland, executables: [:]))
        #expect(status == .portalAvailable)
    }
}
