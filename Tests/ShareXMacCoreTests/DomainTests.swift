import XCTest
@testable import ShareXMacCore

final class DomainTests: XCTestCase {
    func testDelayIsNormalizedToZeroThroughSixty() {
        XCTAssertEqual(CaptureSettings(showCursor: true, delaySeconds: -2).normalizedDelaySeconds, 0)
        XCTAssertEqual(CaptureSettings(delaySeconds: 72).normalizedDelaySeconds, 60)
        XCTAssertEqual(CaptureSettings(delaySeconds: 12.5).normalizedDelaySeconds, 12.5)
    }

    func testStableModeAndActionRawValues() {
        XCTAssertEqual(CaptureMode.fullscreen.rawValue, "fullscreen")
        XCTAssertEqual(CaptureMode.region.rawValue, "region")
        XCTAssertEqual(CaptureMode.window.rawValue, "window")
        XCTAssertEqual(CaptureMode.ocrRegion.rawValue, "ocrRegion")
        XCTAssertEqual(HotkeyAction.fullscreen.rawValue, "fullscreen")
        XCTAssertEqual(HotkeyAction.region.rawValue, "region")
        XCTAssertEqual(HotkeyAction.window.rawValue, "window")
        XCTAssertEqual(HotkeyAction.ocrRegion.rawValue, "ocrRegion")
        XCTAssertEqual(HotkeyAction.history.rawValue, "history")
        XCTAssertEqual(HotkeyAction.imageHistory.rawValue, "imageHistory")
        XCTAssertEqual(HotkeyAction.settings.rawValue, "settings")
    }

    func testCaptureRecordCodableRoundTrip() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = CaptureRecord(id: id, timestamp: date, mode: .window, path: "/tmp/a.png", width: 800, height: 600, windowTitle: "Terminal", applicationName: "Terminal")
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertFalse(settings.capture.showCursor)
        XCTAssertEqual(settings.capture.delaySeconds, 0)
        XCTAssertEqual(settings.ocr.recognitionScale, 1)
        XCTAssertNil(settings.screenshotFolderBookmark)
        XCTAssertEqual(settings.hotkeys.count, 7)
    }
}
