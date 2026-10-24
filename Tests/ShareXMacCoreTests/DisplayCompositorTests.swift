import CoreGraphics
import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Display compositing")
struct DisplayCompositorTests {
    @Test("mixed backing scales and negative origins retain display placement")
    func mixedScalesAndOrigins() throws {
        let left = try image(width: 4, height: 2, color: (1, 0, 0, 1))
        let right = try image(width: 4, height: 2, color: (0, 1, 0, 1))
        let captures = [
            DisplayCompositor.DisplayCapture(image: left, frame: CGRect(x: -2, y: 1, width: 2, height: 1), scale: 2),
            DisplayCompositor.DisplayCapture(image: right, frame: CGRect(x: 0, y: 0, width: 4, height: 2), scale: 1)
        ]

        let result = DisplayCompositor().composite(captures)

        #expect(result.width == 12)
        #expect(result.height == 4)
        #expect(pixel(result, x: 0, y: 2).red > 0.9)
        #expect(pixel(result, x: 1, y: 3).red > 0.9)
        #expect(pixel(result, x: 3, y: 3).red > 0.9)
        #expect(pixel(result, x: 6, y: 1).green > 0.9)
        #expect(pixel(result, x: 10, y: 2).green > 0.9)
        #expect(pixel(result, x: 4, y: 3).green > 0.9)
    }

    @Test("gaps remain transparent while lower scale displays are upsampled")
    func gapsAndUpsampling() throws {
        let left = try image(width: 4, height: 2, color: (1, 0, 0, 1))
        let right = try image(width: 2, height: 1, color: (0, 0, 1, 1))
        let captures = [
            DisplayCompositor.DisplayCapture(image: left, frame: CGRect(x: -2, y: 0, width: 2, height: 1), scale: 2),
            DisplayCompositor.DisplayCapture(image: right, frame: CGRect(x: 2, y: 1, width: 2, height: 1), scale: 1)
        ]

        let result = DisplayCompositor().composite(captures)

        #expect(result.width == 12)
        #expect(result.height == 4)
        #expect(pixel(result, x: 1, y: 0).red > 0.9)
        #expect(pixel(result, x: 9, y: 3).blue > 0.9)
        #expect(pixel(result, x: 5, y: 1).alpha < 0.01)
    }

    @Test("a labeled image keeps its internal top and bottom rows")
    func sourceOrientation() throws {
        let bytes = Data([255, 0, 0, 255, 0, 255, 0, 255,
                          0, 0, 255, 255, 255, 255, 0, 255])
        let pattern = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                              provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
                              shouldInterpolate: false, intent: .defaultIntent)!
        let result = DisplayCompositor().composite([
            .init(image: pattern, frame: CGRect(x: -2, y: -3, width: 2, height: 2), scale: 1)
        ])
        #expect(pixel(result, x: 0, y: 0).red > 0.9)
        #expect(pixel(result, x: 1, y: 0).green > 0.9)
        #expect(pixel(result, x: 0, y: 1).blue > 0.9)
        #expect(pixel(result, x: 1, y: 1).red > 0.9)
        #expect(pixel(result, x: 1, y: 1).green > 0.9)
    }

    private func image(width: Int, height: Int, color: (CGFloat, CGFloat, CGFloat, CGFloat)) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = UInt8(color.0 * 255)
            bytes[index + 1] = UInt8(color.1 * 255)
            bytes[index + 2] = UInt8(color.2 * 255)
            bytes[index + 3] = UInt8(color.3 * 255)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let data = image.dataProvider!.data! as Data
        let index = (y * image.bytesPerRow) + (x * 4)
        return (CGFloat(data[index]) / 255, CGFloat(data[index + 1]) / 255, CGFloat(data[index + 2]) / 255, CGFloat(data[index + 3]) / 255)
    }
}
