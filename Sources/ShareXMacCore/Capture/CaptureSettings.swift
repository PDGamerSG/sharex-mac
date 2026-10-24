public struct CaptureSettings: Codable, Equatable, Sendable {
    public var showCursor: Bool
    public var delaySeconds: Double
    public var copyToClipboard: Bool

    public var normalizedDelaySeconds: Double {
        min(max(delaySeconds, 0), 60)
    }

    public var normalizedDelay: Double { normalizedDelaySeconds }

    public init(showCursor: Bool = false, delaySeconds: Double = 0, copyToClipboard: Bool = true) {
        self.showCursor = showCursor
        self.delaySeconds = delaySeconds
        self.copyToClipboard = copyToClipboard
    }

    private enum CodingKeys: String, CodingKey {
        case showCursor
        case delaySeconds
        case copyToClipboard
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            showCursor: try values.decodeIfPresent(Bool.self, forKey: .showCursor) ?? false,
            delaySeconds: try values.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 0,
            copyToClipboard: try values.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? true
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(showCursor, forKey: .showCursor)
        try values.encode(delaySeconds, forKey: .delaySeconds)
        try values.encode(copyToClipboard, forKey: .copyToClipboard)
    }
}
