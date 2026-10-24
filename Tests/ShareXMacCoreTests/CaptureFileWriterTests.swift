import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShareXMacCore

@Suite("Capture file writing")
struct CaptureFileWriterTests {
    @Test("collisions receive numeric suffixes and preserve earlier captures")
    func collisionSuffixes() throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let first = try CaptureFileWriter().writePNG(image, to: directory.url, date: date)
        let second = try CaptureFileWriter().writePNG(image, to: directory.url, date: date)

        #expect(first.lastPathComponent.hasPrefix("ShareX_"))
        #expect(second.lastPathComponent != first.lastPathComponent)
        #expect(second.lastPathComponent.contains("_1.png"))
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        let firstData = try Data(contentsOf: first)
        let secondData = try Data(contentsOf: second)
        #expect(firstData == secondData)
    }

    @Test("writes a readable PNG without leaving temporary files")
    func atomicPNGOutput() throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let output = try CaptureFileWriter().writePNG(image, to: directory.url, date: Date(timeIntervalSince1970: 1_735_689_600))

        #expect(CGImageSourceCreateWithURL(output as CFURL, nil) != nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(files.first?.pathExtension == "png")
    }

    private func onePixelImage() throws -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
