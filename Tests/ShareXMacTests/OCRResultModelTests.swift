import AppKit
import Combine
import ShareXMacCore
import Testing
@testable import ShareXMac

@Suite("OCR clipboard")
@MainActor struct OCRResultModelTests {
    @Test("successful recognition copies the displayed text automatically",
          arguments: [(false, "FIRST LINE\nSECOND LINE"), (true, "FIRST LINE SECOND LINE")])
    func automaticCopy(singleLine: Bool, expected: String) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous clipboard", forType: .string)
        let model = OCRResultModel(image: try fixture(), service: VisionOCRService(),
                                   settings: OCRSettings(languages: ["en-US"]), pasteboard: pasteboard)
        model.singleLine = singleLine

        await finishRecognition(model) { model.startIfNeeded() }

        #expect(model.text == "FIRST LINE\nSECOND LINE")
        #expect(pasteboard.string(forType: .string) == expected)

        // Try Again also copies its new result using the current display format.
        pasteboard.clearContents()
        pasteboard.setString("Clipboard changed after recognition", forType: .string)
        await finishRecognition(model) { model.recognize() }
        #expect(pasteboard.string(forType: .string) == expected)
    }

    @Test("empty or failed recognition preserves the clipboard", arguments: [false, true])
    func noTextPreservesClipboard(failed: Bool) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Keep this text", forType: .string)
        let model = OCRResultModel(image: try fixture(lines: []), service: VisionOCRService(),
            settings: OCRSettings(languages: [failed ? "made-up-LANG" : "en-US"]), pasteboard: pasteboard)

        await finishRecognition(model) { model.startIfNeeded() }

        #expect(model.text.isEmpty)
        #expect((model.error != nil) == failed)
        #expect(pasteboard.string(forType: .string) == "Keep this text")
    }

    private func finishRecognition(_ model: OCRResultModel, start: () -> Void) async {
        await withCheckedContinuation { continuation in
            var observation: AnyCancellable?
            observation = model.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
                observation?.cancel()
                continuation.resume()
            }
            start()
        }
    }

    private func fixture(lines: [String] = ["FIRST LINE", "SECOND LINE"]) throws -> CGImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 360,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 360).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 52, weight: .medium), .foregroundColor: NSColor.black
        ]
        for (index, text) in lines.enumerated() {
            (text as NSString).draw(at: NSPoint(x: 40, y: 260 - index * 100), withAttributes: attributes)
        }
        return try #require(bitmap.cgImage)
    }
}
