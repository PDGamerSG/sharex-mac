public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case fullscreen
    case region
    case window
    case ocrRegion
    // Kept only so older settings files can decode before migration removes it.
    case history
    case imageHistory
    case settings

    public static let allCases: [HotkeyAction] = [
        .fullscreen, .region, .window, .ocrRegion, .imageHistory, .settings
    ]
}
