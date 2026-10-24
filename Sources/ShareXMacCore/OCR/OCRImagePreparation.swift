import CoreGraphics

public enum OCRImagePreparation {
    /// RGBA preprocessing is bounded to 256 MB of pixel storage per image.
    public static let maximumPixelCount = 64_000_000

    public static func dimensions(width: Int, height: Int, scale: Double) throws -> CGSize {
        guard width > 0, height > 0 else { throw OCRError.invalidImage }
        let scale = scale.isFinite ? min(max(scale, 1), 4) : 1
        let width = ceil(Double(width) * scale)
        let height = ceil(Double(height) * scale)
        guard width <= Double(maximumPixelCount), height <= Double(maximumPixelCount),
              width * height <= Double(maximumPixelCount) else { throw OCRError.imageTooLarge }
        return CGSize(width: width, height: height)
    }

    static func prepare(_ image: CGImage, scale: Double) throws -> CGImage {
        let size = try dimensions(width: image.width, height: image.height, scale: scale)
        guard Int(size.width) != image.width || Int(size.height) != image.height else { return image }
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OCRError.invalidImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let result = context.makeImage() else { throw OCRError.invalidImage }
        return result
    }
}
