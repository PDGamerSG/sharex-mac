public struct OCRSettings: Codable, Equatable, Sendable {
    public var recognitionScale: Double
    public var languages: [String]
    public var usesLanguageCorrection: Bool

    public init(recognitionScale: Double = 1, languages: [String] = [], usesLanguageCorrection: Bool = true) {
        self.recognitionScale = recognitionScale
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    private enum CodingKeys: String, CodingKey {
        case recognitionScale, languages, usesLanguageCorrection
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            recognitionScale: try values.decodeIfPresent(Double.self, forKey: .recognitionScale) ?? 1,
            languages: try values.decodeIfPresent([String].self, forKey: .languages) ?? [],
            usesLanguageCorrection: try values.decodeIfPresent(Bool.self, forKey: .usesLanguageCorrection) ?? true
        )
    }
}
