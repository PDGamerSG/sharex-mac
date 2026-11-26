public enum ScreenshotResolution: String, Codable, CaseIterable, Sendable {
    case full, threeQuarter, half

    public var title: String {
        switch self {
        case .full: "Full resolution (100%)"
        case .threeQuarter: "Reduced resolution (75%)"
        case .half: "Reduced resolution (50%)"
        }
    }

    public var scale: Double {
        switch self {
        case .full: 1
        case .threeQuarter: 0.75
        case .half: 0.5
        }
    }
}
