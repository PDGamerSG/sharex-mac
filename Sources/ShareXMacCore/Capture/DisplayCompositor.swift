import CoreGraphics
import Foundation

/// Composites screenshots from displays whose coordinates are expressed in the
/// same logical desktop coordinate space.
public struct DisplayCompositor: Sendable {
    public struct DisplayCapture {
        public let image: CGImage
        public let frame: CGRect
        public let scale: CGFloat

        public init(image: CGImage, frame: CGRect, scale: CGFloat) {
            self.image = image
            self.frame = frame
            self.scale = max(scale, 0.01)
        }
    }

    public init() {}

    public static func composite(_ displays: [DisplayCapture]) -> CGImage {
        DisplayCompositor().composite(displays)
    }

    /// Returns one image covering the logical union of all display frames.
    /// The output uses the largest backing scale so that logical origins stay
    /// stable when displays have different scale factors.
    public func composite(_ displays: [DisplayCapture]) -> CGImage {
        guard let first = displays.first else {
            return Self.emptyImage()
        }

        let bounds = displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let outputScale = displays.map(\.scale).max() ?? 1
        let width = max(1, Int(ceil(bounds.width * outputScale)))
        let height = max(1, Int(ceil(bounds.height * outputScale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return Self.emptyImage()
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        for display in displays {
            let destination = CGRect(x: (display.frame.minX - bounds.minX) * outputScale,
                                     y: (bounds.maxY - display.frame.maxY) * outputScale,
                                     width: display.frame.width * outputScale,
                                     height: display.frame.height * outputScale)
            context.draw(display.image, in: destination)
        }
        return context.makeImage() ?? Self.emptyImage()
    }

    private static func emptyImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}
