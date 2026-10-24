import Foundation

public struct OCRSettings: Codable, Equatable, Sendable {
    public var recognitionScale: Double
    public var languages: [String]
    public var usesLanguageCorrection: Bool

    public init(recognitionScale: Double = 1, languages: [String] = [], usesLanguageCorrection: Bool = true) {
        self.recognitionScale = recognitionScale
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var capture: CaptureSettings
    public var ocr: OCRSettings
    public var screenshotFolderBookmark: Data?
    public var hotkeys: [HotkeyAction: HotkeyBinding]

    public init(capture: CaptureSettings = CaptureSettings(), ocr: OCRSettings = OCRSettings(), screenshotFolderBookmark: Data? = nil, hotkeys: [HotkeyAction: HotkeyBinding] = AppSettings.defaultHotkeys) {
        self.capture = capture
        self.ocr = ocr
        self.screenshotFolderBookmark = screenshotFolderBookmark
        self.hotkeys = hotkeys
    }

    public static let defaultHotkeys: [HotkeyAction: HotkeyBinding] = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, HotkeyBinding()) })
}
