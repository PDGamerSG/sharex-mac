import Foundation
import ShareXLinuxCore
import Testing

struct LinuxControllerTests {
    @Test("a published image and its history use the final output size; OCR keeps original pixels")
    func captureAndPublish() async throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let store = try LinuxScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let workflow = LinuxAppController(
            capture: { _, _, temporary in
                let file = temporary.appendingPathComponent("capture.png")
                try Data("capture".utf8).write(to: file)
                return LinuxCapturedImage(path: file, width: 120, height: 80)
            },
            resize: { url, _, _, _ in url },
            insert: { try await store.insert($0) },
            copyImage: { _ in throw LinuxSupportError.unsupported("The clipboard is unavailable.") }
        )
        var settings = LinuxCaptureSettings(screenshotFolderPath: directory.url.path)
        settings.screenshotResolution = .half
        let screenshot = try await workflow.capture(.region, settings: settings)
        #expect(screenshot.record.width == 60)
        #expect(screenshot.record.height == 40)
        #expect(screenshot.warning != nil)
        #expect(FileManager.default.fileExists(atPath: screenshot.record.path))

        let ocr = try await workflow.capture(.ocrRegion, settings: settings)
        #expect(ocr.record.width == 120)
        #expect(ocr.record.height == 80)
        #expect(ocr.warning == nil)
        let records = try await store.list().map(\.record)
        #expect(records.map(\.id) == [ocr.record.id, screenshot.record.id])
        #expect(records.map(\.path) == [ocr.record.path, screenshot.record.path])
        #expect(records.map(\.width) == [ocr.record.width, screenshot.record.width])
    }

    @Test("cancelled capture and failed publication leave history empty")
    func failures() async throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let store = try LinuxScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let workflow = LinuxAppController(
            capture: { mode, _, temporary in
                if mode == .region { throw CancellationError() }
                return LinuxCapturedImage(path: temporary.appendingPathComponent("missing"), width: 10, height: 10)
            },
            resize: { url, _, _, _ in url },
            insert: { try await store.insert($0) },
            copyImage: { _ in Issue.record("Unexpected image copy") }
        )
        let settings = LinuxCaptureSettings(screenshotFolderPath: directory.url.path)
        await #expect(throws: CancellationError.self) { try await workflow.capture(.region, settings: settings) }
        await #expect(throws: (any Error).self) { try await workflow.capture(.fullscreen, settings: settings) }
        #expect(try await store.list().isEmpty)
    }
}
