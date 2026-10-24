import AppKit
import CoreGraphics
import Testing
@testable import ShareXMacCore

@Suite("Offline Vision OCR")
struct OCRVisionIntegrationTests {
    @Test("discovers languages supported by accurate local recognition")
    func languages() throws {
        let supported = try VisionOCRService().supportedLanguages()
        #expect(supported.contains("en-US"))
        #expect(Set(supported).count == supported.count)
    }

    @Test("recognizes a rendered multiline image in reading order")
    @MainActor func renderedMultiline() async throws {
        let image = try fixture()
        let service = VisionOCRService()
        let settings = OCRSettings(recognitionScale: 1, languages: ["en-US"], usesLanguageCorrection: true)
        let result = try await service.recognize(image: image, settings: settings)
        #expect(result == "FIRST LINE\nSECOND LINE\nTHIRD LINE")
        let scaledSettings = OCRSettings(recognitionScale: 2, languages: ["en-US"], usesLanguageCorrection: true)
        let singleLine = try await service.recognize(image: image, settings: scaledSettings, singleLine: true)
        #expect(singleLine == "FIRST LINE SECOND LINE THIRD LINE")
    }

    @Test("unsupported recognition languages are rejected with the requested identifier")
    @MainActor func invalidLanguage() async throws {
        let image = try fixture()
        await #expect(throws: OCRError.unsupportedLanguages(["made-up-LANG"])) {
            try await VisionOCRService().recognize(image: image, settings: OCRSettings(languages: ["made-up-LANG"]))
        }
    }

    @Test("an already cancelled task never returns recognized text")
    @MainActor func cancelledRecognition() async throws {
        let image = try fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VisionOCRService().recognize(image: image, settings: OCRSettings())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("an image without text produces an empty result")
    @MainActor func blankImage() async throws {
        let image = try fixture(lines: [])
        #expect(try await VisionOCRService().recognize(image: image, settings: OCRSettings(languages: ["en-US"])) == "")
    }

    @MainActor private func fixture(lines: [String] = ["FIRST LINE", "SECOND LINE", "THIRD LINE"]) throws -> CGImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 360,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 360).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 52, weight: .medium), .foregroundColor: NSColor.black
        ]
        for (index, text) in lines.enumerated() {
            (text as NSString).draw(at: NSPoint(x: 40, y: 260 - (index * 100)), withAttributes: attributes)
        }
        return try #require(bitmap.cgImage)
    }
}
