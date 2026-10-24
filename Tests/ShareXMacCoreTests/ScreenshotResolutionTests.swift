import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShareXMacCore

@Suite("Screenshot resolution")
struct ScreenshotResolutionTests {
    @Test("full resolution keeps the original pixels, dimensions and color profile")
    func fullResolution() throws {
        let source = try image(width: 8, height: 4)
        let output = try ScreenshotResolution.full.prepare(source)
        #expect(output === source)
        let composite = DisplayCompositor.composite([
            .init(image: source, frame: CGRect(x: -4, y: 0, width: 4, height: 2), scale: 2)
        ])
        #expect(composite === source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try CaptureFileWriter.writePNG(output, to: directory)
        let saved = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(saved, 0, nil))
        #expect(decoded.width == 8 && decoded.height == 4)
        #expect(decoded.colorSpace?.name == source.colorSpace?.name)
        #expect(try pixels(decoded) == pixels(source))
    }

    @Test("reduced resolution scales both dimensions and preserves transparency and color space")
    func reducedResolution() throws {
        let source = try image(width: 8, height: 4)
        let medium = try ScreenshotResolution.threeQuarter.prepare(source)
        #expect(medium.width == 6 && medium.height == 3)
        let small = try ScreenshotResolution.half.prepare(source)
        #expect(small.width == 4 && small.height == 2)
        #expect(small.colorSpace?.name == source.colorSpace?.name)
        #expect(try pixels(small).last == 0)
        let tiny = try ScreenshotResolution.half.prepare(image(width: 1, height: 1))
        #expect(tiny.width == 1 && tiny.height == 1)
    }

    @Test("settings upgrades preserve existing choices and default to full resolution")
    func settingsUpgrade() throws {
        let legacy = Data(#"{"showCursor":true,"delaySeconds":7,"copyToClipboard":false}"#.utf8)
        var decoded = try JSONDecoder().decode(CaptureSettings.self, from: legacy)
        #expect(decoded.screenshotResolution == .full)
        #expect(decoded.showCursor && decoded.delaySeconds == 7 && !decoded.copyToClipboard)
        decoded.screenshotResolution = .threeQuarter
        let saved = try JSONEncoder().encode(decoded)
        #expect(try JSONDecoder().decode(CaptureSettings.self, from: saved) == decoded)
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [0.8, 0.25, 0.4, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                            bytesPerRow: image.width * 4, space: image.colorSpace!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
}
