import Foundation
import ShareXLinuxCore
import Testing

struct LinuxOCRClipboardTests {
    @Test("Tesseract language output ignores its header")
    func parsesLanguages() {
        let output = "List of available languages in \"/usr/share/tessdata/\":\neng\nfra\n"
        #expect(LinuxOCRService.parseLanguages(output) == ["eng", "fra"])
    }

    @Test("clipboard plans select the desktop helper and preserve arguments")
    func clipboardPlan() throws {
        let wayland = LinuxDesktopEnvironment(session: .wayland, executables: ["wl-copy": URL(fileURLWithPath: "/usr/bin/wl-copy")])
        let plan = try LinuxClipboardService.plan(for: wayland, kind: .text)
        #expect(plan.executable.lastPathComponent == "wl-copy")
        #expect(plan.arguments == [])
    }
}
