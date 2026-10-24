import CoreGraphics

public struct CapturedDesktop: Sendable {
    public let image: CGImage
    public let geometry: DesktopGeometry
    public let displayCount: Int

    public init(image: CGImage, geometry: DesktopGeometry, displayCount: Int = 1) {
        self.image = image
        self.geometry = geometry
        self.displayCount = displayCount
    }

    public func crop(appKitRegion: CGRect) -> CGImage? {
        guard let pixels = geometry.pixelRect(forAppKit: appKitRegion, imageWidth: image.width, imageHeight: image.height) else { return nil }
        return image.cropping(to: pixels)
    }
}
