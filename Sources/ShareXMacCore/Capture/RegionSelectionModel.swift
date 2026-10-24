import CoreGraphics

public struct RegionSelectionModel: Sendable {
    public init() {}

    public func selection(start: CGPoint, end: CGPoint, in bounds: CGRect) -> CGRect? {
        guard [start.x, start.y, end.x, end.y, bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              !bounds.isNull, !bounds.isEmpty else { return nil }

        let dragged = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let clipped = dragged.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
}
