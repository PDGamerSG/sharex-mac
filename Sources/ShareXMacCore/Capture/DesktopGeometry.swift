import CoreGraphics

/// Quartz uses a top-left origin on the primary display; AppKit uses bottom-left.
public struct DesktopGeometry: Sendable {
    public let quartzBounds: CGRect
    public let mainDisplayHeight: CGFloat

    public init(quartzBounds: CGRect, mainDisplayHeight: CGFloat) {
        self.quartzBounds = quartzBounds
        self.mainDisplayHeight = mainDisplayHeight
    }

    public var appKitBounds: CGRect { appKitRect(fromQuartz: quartzBounds) }

    public func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func pixelRect(forAppKit rect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard quartzBounds.width > 0, quartzBounds.height > 0,
              imageWidth > 0, imageHeight > 0 else { return nil }
        let quartzRect = appKitRect(fromQuartz: rect).intersection(quartzBounds)
        guard !quartzRect.isNull, !quartzRect.isEmpty else { return nil }
        let scaleX = CGFloat(imageWidth) / quartzBounds.width
        let scaleY = CGFloat(imageHeight) / quartzBounds.height
        return CGRect(x: (quartzRect.minX - quartzBounds.minX) * scaleX,
                      y: (quartzRect.minY - quartzBounds.minY) * scaleY,
                      width: quartzRect.width * scaleX, height: quartzRect.height * scaleY)
            .integral.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }
}
