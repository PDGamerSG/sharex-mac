public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case fullscreen
    case region
    case window
    case ocrRegion
    case history
    case imageHistory
    case settings
}

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(key: String = "", modifiers: [String] = []) {
        self.key = key
        self.modifiers = modifiers
    }
}
