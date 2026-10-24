import CoreGraphics
import Testing
@testable import ShareXMacCore

@Suite("OCR reading order")
struct OCRTextOrderingTests {
    @Test("orders shuffled observations top to bottom and left to right within a row")
    func readingOrder() {
        let lines = [
            line("Bottom line", x: 0.1, y: 0.2),
            line("world", x: 0.5, y: 0.802),
            line("Hello", x: 0.1, y: 0.8),
            line("Middle line", x: 0.1, y: 0.5)
        ]
        #expect(OCRTextOrdering.text(from: lines) == "Hello world\nMiddle line\nBottom line")
        #expect(OCRTextOrdering.text(from: lines.reversed()) == "Hello world\nMiddle line\nBottom line")
    }

    @Test("single-line output removes embedded whitespace and line breaks")
    func singleLine() {
        let lines = [line("Second\tline", x: 0.1, y: 0.3), line(" First  line ", x: 0.1, y: 0.8)]
        #expect(OCRTextOrdering.text(from: lines, singleLine: true) == "First line Second line")
    }

    @Test("empty and whitespace-only observations produce no text")
    func emptyResults() {
        #expect(OCRTextOrdering.text(from: []) == "")
        #expect(OCRTextOrdering.text(from: [line(" \n ", x: 0.1, y: 0.2)]) == "")
    }

    @Test("geometry ties use text as a deterministic final ordering key")
    func equalGeometry() {
        #expect(OCRTextOrdering.text(from: [line("Beta", x: 0.1, y: 0.8), line("Alpha", x: 0.1, y: 0.8)]) == "Alpha Beta")
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat) -> OCRTextLine {
        OCRTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.3, height: 0.08))
    }
}

@Suite("OCR image preparation")
struct OCRImagePreparationTests {
    @Test("recognition scale is clamped to one through four")
    func scaleBounds() throws {
        #expect(try OCRImagePreparation.dimensions(width: 100, height: 50, scale: 0.25) == CGSize(width: 100, height: 50))
        #expect(try OCRImagePreparation.dimensions(width: 100, height: 50, scale: 10) == CGSize(width: 400, height: 200))
        #expect(try OCRImagePreparation.dimensions(width: 100, height: 50, scale: 1.5) == CGSize(width: 150, height: 75))
        #expect(try OCRImagePreparation.dimensions(width: 100, height: 50, scale: .nan) == CGSize(width: 100, height: 50))
    }

    @Test("invalid or oversized image dimensions are rejected before allocating pixels")
    func memoryLimit() throws {
        #expect(throws: OCRError.invalidImage) { try OCRImagePreparation.dimensions(width: 0, height: 10, scale: 1) }
        #expect(throws: OCRError.imageTooLarge) { try OCRImagePreparation.dimensions(width: 10_000, height: 10_000, scale: 1) }
        #expect(throws: OCRError.imageTooLarge) { try OCRImagePreparation.dimensions(width: 4_000, height: 4_000, scale: 4) }
        #expect(throws: OCRError.imageTooLarge) { try OCRImagePreparation.dimensions(width: Int.max, height: Int.max, scale: 4) }
    }
}
