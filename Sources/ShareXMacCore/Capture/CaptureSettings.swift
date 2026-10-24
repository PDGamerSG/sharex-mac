public struct CaptureSettings: Codable, Equatable, Sendable {
    public var showCursor: Bool
    public var delaySeconds: Double

    public var normalizedDelaySeconds: Double {
        min(max(delaySeconds, 0), 60)
    }

    public var normalizedDelay: Double { normalizedDelaySeconds }

    public init(showCursor: Bool = false, delaySeconds: Double = 0) {
        self.showCursor = showCursor
        self.delaySeconds = delaySeconds
    }
}
