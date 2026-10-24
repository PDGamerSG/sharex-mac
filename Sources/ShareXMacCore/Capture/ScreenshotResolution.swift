import CoreGraphics
import Foundation

public enum ScreenshotResolution: String, Codable, CaseIterable, Sendable {
    case full, threeQuarter, half

    public var title: String {
        switch self {
        case .full: "Full resolution (100%)"
        case .threeQuarter: "Reduced resolution (75%)"
        case .half: "Reduced resolution (50%)"
        }
    }

    /// Full resolution bypasses rendering entirely. Only an explicit reduction
    /// resamples pixels; all choices are still saved as lossless PNG.
    public func prepare(_ image: CGImage) throws -> CGImage {
        guard self != .full else { return image }
        let scale = self == .threeQuarter ? 0.75 : 0.5
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PreparationError.unableToResize
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw PreparationError.unableToResize }
        return result
    }

    private enum PreparationError: LocalizedError {
        case unableToResize
        var errorDescription: String? { "The screenshot could not be resized. Try full resolution in Capture settings." }
    }
}
