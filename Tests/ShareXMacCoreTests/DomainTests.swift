import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Domain models")
struct DomainTests {
    @Test("delay is normalized to zero through sixty")
    func delayIsNormalizedToZeroThroughSixty() {
        #expect(CaptureSettings(showCursor: true, delaySeconds: -2).normalizedDelaySeconds == 0)
        #expect(CaptureSettings(delaySeconds: 72).normalizedDelaySeconds == 60)
        #expect(CaptureSettings(delaySeconds: 12.5).normalizedDelaySeconds == 12.5)
    }

    @Test("mode and action raw values are stable")
    func stableModeAndActionRawValues() {
        #expect(CaptureMode.fullscreen.rawValue == "fullscreen")
        #expect(CaptureMode.region.rawValue == "region")
        #expect(CaptureMode.window.rawValue == "window")
        #expect(CaptureMode.ocrRegion.rawValue == "ocrRegion")
        #expect(HotkeyAction.fullscreen.rawValue == "fullscreen")
        #expect(HotkeyAction.region.rawValue == "region")
        #expect(HotkeyAction.window.rawValue == "window")
        #expect(HotkeyAction.ocrRegion.rawValue == "ocrRegion")
        #expect(HotkeyAction.history.rawValue == "history")
        #expect(HotkeyAction.imageHistory.rawValue == "imageHistory")
        #expect(HotkeyAction.settings.rawValue == "settings")
    }

    @Test("capture record Codable round trip")
    func captureRecordCodableRoundTrip() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = CaptureRecord(id: id, timestamp: date, mode: .window, path: "/tmp/a.png", width: 800, height: 600, windowTitle: "Terminal", applicationName: "Terminal")
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    @Test("default settings include every action and OCR default")
    func defaultSettings() {
        let settings = AppSettings()
        #expect(settings.capture.showCursor == false)
        #expect(settings.capture.delaySeconds == 0)
        #expect(settings.ocr.recognitionScale == 1)
        #expect(settings.ocr.languages.isEmpty)
        #expect(settings.ocr.usesLanguageCorrection)
        #expect(settings.screenshotFolderBookmark == nil)
        #expect(Set(settings.hotkeys.keys) == Set(HotkeyAction.allCases))
        for action in HotkeyAction.allCases {
            #expect(settings.hotkeys[action] == HotkeyBinding())
        }
    }
}
