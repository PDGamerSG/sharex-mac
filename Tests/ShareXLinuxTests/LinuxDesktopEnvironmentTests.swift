import Foundation
import ShareXLinuxCore
import Testing

struct LinuxDesktopEnvironmentTests {
    @Test("Wayland takes precedence when both display variables exist")
    func waylandPrecedence() {
        let environment = LinuxDesktopEnvironment.detect(environment: ["WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0"], which: { name in
            URL(fileURLWithPath: "/usr/bin/\(name)")
        })
        #expect(environment.session == .wayland)
        #expect(environment.has("grim"))
    }

    @Test("X11 chooses gnome-screenshot before ImageMagick")
    func x11Plan() throws {
        let environment = LinuxDesktopEnvironment.detect(environment: ["DISPLAY": ":0"], which: { name in
            name == "gnome-screenshot" || name == "import" ? URL(fileURLWithPath: "/usr/bin/\(name)") : nil
        })
        let plan = try environment.capturePlan(for: .fullscreen)
        #expect(plan.executable.lastPathComponent == "gnome-screenshot")
        #expect(plan.arguments.first == "-f")
    }
}
