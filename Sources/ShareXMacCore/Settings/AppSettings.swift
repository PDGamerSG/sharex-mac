import Foundation
import ShareXCore

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

    public static let defaultHotkeys: [HotkeyAction: HotkeyBinding] = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { action in
        let binding: HotkeyBinding = switch action {
        case .region: HotkeyBinding(key: "p", modifiers: ["option"])
        case .ocrRegion: HotkeyBinding(key: "p", modifiers: ["shift"])
        default: HotkeyBinding()
        }
        return (action, binding)
    })
}
