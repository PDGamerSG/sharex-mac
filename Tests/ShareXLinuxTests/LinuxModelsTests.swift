import Foundation
import ShareXLinuxCore
import Testing

struct LinuxModelsTests {
    @Test("Linux capture settings clamp delay and preserve defaults")
    func captureSettings() {
        let settings = LinuxCaptureSettings(delaySeconds: 120)
        #expect(settings.normalizedDelaySeconds == 60)
        #expect(settings.copyToClipboard)
        #expect(!settings.showCursor)
    }

    @Test("Linux modes and actions keep stable raw values")
    func stableRawValues() {
        #expect(LinuxCaptureMode.allCases.map(\.rawValue) == ["fullscreen", "region", "window", "ocrRegion"])
        #expect(LinuxAction.region.rawValue == "region")
    }

    @Test("default Linux settings include the same capture shortcuts")
    func defaults() {
        let settings = LinuxAppSettings()
        #expect(settings.hotkeys[LinuxAction.region.rawValue]?.first?.key == "p")
        #expect(settings.hotkeys[LinuxAction.region.rawValue]?.first?.modifiers == ["alt"])
        #expect(settings.hotkeys[LinuxAction.ocrRegion.rawValue]?.first?.modifiers == ["shift"])
    }

    @Test("Linux capture records round trip through Codable")
    func recordCodable() throws {
        let record = LinuxCaptureRecord(mode: .window, path: "/tmp/a.png", width: 800, height: 600,
                                        windowTitle: "Terminal", applicationName: "xterm", displayCount: 1)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(LinuxCaptureRecord.self, from: data) == record)
    }

    @Test("portable capture and OCR options round trip with legacy defaults")
    func portableOptions() throws {
        let settings = LinuxAppSettings(
            capture: LinuxCaptureSettings(delaySeconds: 3, screenshotResolution: .half),
            ocr: LinuxOCRSettings(recognitionScale: 2),
            launchAtLogin: true
        )
        let decoded = try JSONDecoder().decode(LinuxAppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.capture.screenshotResolution == .half)
        #expect(decoded.capture.options.screenshotResolution == .half)
        #expect(decoded.ocr.options.recognitionScale == 2)
        #expect(decoded.launchAtLogin)

        let legacy = try JSONDecoder().decode(LinuxAppSettings.self, from: Data(#"{"capture":{"showCursor":true}}"#.utf8))
        #expect(legacy.capture.screenshotResolution == .full)
        #expect(legacy.ocr.recognitionScale == 1)
        #expect(!legacy.launchAtLogin)
    }

    @Test("settings validation permits additive bindings and rejects duplicate semantics")
    func hotkeyValidation() throws {
        var settings = LinuxAppSettings()
        settings.hotkeys[LinuxAction.region.rawValue] = [
            LinuxHotkeyBinding(key: "p", modifiers: ["alt"]),
            LinuxHotkeyBinding(key: "F9", modifiers: ["control", "shift"])
        ]
        let validated = try settings.validated()
        #expect(validated.hotkeys[LinuxAction.region.rawValue]?.count == 2)
        settings.hotkeys[LinuxAction.settings.rawValue] = [LinuxHotkeyBinding(key: "P", modifiers: ["option"])]
        #expect(throws: LinuxSettingsValidationError.self) { try settings.validated() }
        settings.hotkeys[LinuxAction.settings.rawValue] = [LinuxHotkeyBinding(key: "F9", modifiers: ["bogus"])]
        #expect(throws: LinuxSettingsValidationError.self) { try settings.validated() }
    }
}

struct LinuxTestTemporaryDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXLinuxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
}
