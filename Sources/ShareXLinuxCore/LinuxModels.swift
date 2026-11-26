import Foundation
import ShareXCore

public enum LinuxCaptureMode: String, Codable, CaseIterable, Sendable {
    case fullscreen
    case region
    case window
    case ocrRegion
}

public enum ShareXLinuxCore {
    public static let productName = "ShareX Linux"
}

public enum LinuxAction: String, Codable, CaseIterable, Hashable, Sendable {
    case fullscreen
    case region
    case window
    case ocrRegion
    case history
    case settings
    case quit
}

public struct LinuxHotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(key: String = "", modifiers: [String] = []) {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^f([1-9]|[12][0-9]|3[0-5])$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            self.key = "F" + value.dropFirst()
        } else {
            self.key = value.count == 1 && value.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic })
                ? value.lowercased() : value
        }
        self.modifiers = modifiers.map(Self.normalizedModifier)
    }

    public var displayName: String {
        (modifiers + [key.uppercased()]).joined(separator: "+")
    }

    public static func normalizedModifier(_ modifier: String) -> String {
        switch modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cmd", "command", "super", "meta", "win", "windows": return "super"
        case "alt", "option", "mod1": return "alt"
        case "ctrl", "control", "ctl": return "control"
        case "mod4": return "super"
        case "shift": return "shift"
        default: return modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private enum CodingKeys: String, CodingKey { case key, modifiers }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try values.decodeIfPresent(String.self, forKey: .key) ?? "",
                  modifiers: try values.decodeIfPresent([String].self, forKey: .modifiers) ?? [])
    }
}

public struct LinuxCaptureSettings: Codable, Equatable, Sendable {
    public var showCursor: Bool
    public var delaySeconds: Double
    public var copyToClipboard: Bool
    public var screenshotFolderPath: String
    public var screenshotResolution: ScreenshotResolution

    public var normalizedDelaySeconds: Double {
        min(max(delaySeconds.isFinite ? delaySeconds : 0, 0), 60)
    }

    public var options: CaptureSettings {
        CaptureSettings(showCursor: showCursor, delaySeconds: delaySeconds,
                        copyToClipboard: copyToClipboard, screenshotResolution: screenshotResolution)
    }

    public init(showCursor: Bool = false, delaySeconds: Double = 0, copyToClipboard: Bool = true,
                screenshotFolderPath: String = "", screenshotResolution: ScreenshotResolution = .full) {
        self.showCursor = showCursor
        self.delaySeconds = delaySeconds
        self.copyToClipboard = copyToClipboard
        self.screenshotFolderPath = screenshotFolderPath
        self.screenshotResolution = screenshotResolution
    }

    private enum CodingKeys: String, CodingKey {
        case showCursor, delaySeconds, copyToClipboard, screenshotFolderPath, screenshotResolution
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(showCursor: try values.decodeIfPresent(Bool.self, forKey: .showCursor) ?? false,
                  delaySeconds: try values.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 0,
                  copyToClipboard: try values.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? true,
                  screenshotFolderPath: try values.decodeIfPresent(String.self, forKey: .screenshotFolderPath) ?? "",
                  screenshotResolution: (try? values.decode(ScreenshotResolution.self, forKey: .screenshotResolution)) ?? .full)
    }
}

public struct LinuxOCRSettings: Codable, Equatable, Sendable {
    public var recognitionScale: Double
    public var languages: [String]
    public var usesLanguageCorrection: Bool

    public var options: OCRSettings {
        OCRSettings(recognitionScale: recognitionScale, languages: languages,
                    usesLanguageCorrection: usesLanguageCorrection)
    }

    public init(recognitionScale: Double = 1, languages: [String] = [], usesLanguageCorrection: Bool = true) {
        self.recognitionScale = recognitionScale
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    private enum CodingKeys: String, CodingKey { case recognitionScale, languages, usesLanguageCorrection }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recognitionScale: (try? values.decode(Double.self, forKey: .recognitionScale)) ?? 1,
                  languages: try values.decodeIfPresent([String].self, forKey: .languages) ?? [],
                  usesLanguageCorrection: try values.decodeIfPresent(Bool.self, forKey: .usesLanguageCorrection) ?? true)
    }
}

public enum LinuxSettingsValidationError: Error, LocalizedError, Equatable, Sendable {
    case unknownAction(String)
    case invalidKey(action: String, index: Int, key: String)
    case invalidModifier(action: String, index: Int, modifier: String)
    case duplicateShortcut(firstAction: String, secondAction: String, key: String, modifiers: [String])
    case invalidDelay
    case invalidRecognitionScale
    case invalidLanguage

    public var errorDescription: String? {
        switch self {
        case .unknownAction(let action): return "Unknown Linux action \(action)."
        case .invalidKey(let action, let index, let key): return "Invalid shortcut key \(key) for \(action) binding \(index + 1)."
        case .invalidModifier(let action, let index, let modifier): return "Invalid shortcut modifier \(modifier) for \(action) binding \(index + 1)."
        case .duplicateShortcut(let first, let second, let key, let modifiers):
            let prefix = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "+"
            return "The shortcut \(prefix)\(key) is assigned to both \(first) and \(second)."
        case .invalidDelay: return "Capture delay must be finite and between zero and sixty seconds."
        case .invalidRecognitionScale: return "OCR recognition scale must be finite and between one and four."
        case .invalidLanguage: return "OCR language identifiers cannot be empty."
        }
    }
}

public struct LinuxAppSettings: Codable, Equatable, Sendable {
    public var capture: LinuxCaptureSettings
    public var ocr: LinuxOCRSettings
    public var hotkeys: [String: [LinuxHotkeyBinding]]
    public var startHidden: Bool
    public var launchAtLogin: Bool

    public init(capture: LinuxCaptureSettings = LinuxCaptureSettings(), ocr: LinuxOCRSettings = LinuxOCRSettings(),
                hotkeys: [String: [LinuxHotkeyBinding]] = LinuxAppSettings.defaultHotkeys,
                startHidden: Bool = false, launchAtLogin: Bool = false) {
        self.capture = capture
        self.ocr = ocr
        self.hotkeys = hotkeys
        self.startHidden = startHidden
        self.launchAtLogin = launchAtLogin
    }

    public static let defaultHotkeys: [String: [LinuxHotkeyBinding]] = [
        LinuxAction.fullscreen.rawValue: [],
        LinuxAction.region.rawValue: [LinuxHotkeyBinding(key: "p", modifiers: ["alt"])],
        LinuxAction.window.rawValue: [],
        LinuxAction.ocrRegion.rawValue: [LinuxHotkeyBinding(key: "p", modifiers: ["shift"])],
        LinuxAction.history.rawValue: [],
        LinuxAction.settings.rawValue: [],
        LinuxAction.quit.rawValue: []
    ]

    public func validated() throws -> LinuxAppSettings {
        var result = self
        guard result.capture.delaySeconds.isFinite, (0...60).contains(result.capture.delaySeconds) else {
            throw LinuxSettingsValidationError.invalidDelay
        }
        guard result.ocr.recognitionScale.isFinite, (1...4).contains(result.ocr.recognitionScale) else {
            throw LinuxSettingsValidationError.invalidRecognitionScale
        }
        guard result.ocr.languages.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LinuxSettingsValidationError.invalidLanguage
        }
        let allowedModifiers = Set(["control", "alt", "shift", "super"])
        var seen: [String: (action: String, binding: LinuxHotkeyBinding)] = [:]
        for action in result.hotkeys.keys {
            guard LinuxAction(rawValue: action) != nil else { throw LinuxSettingsValidationError.unknownAction(action) }
        }
        for action in LinuxAction.allCases {
            var bindings = result.hotkeys[action.rawValue] ?? []
            for index in bindings.indices {
                let binding = bindings[index]
                guard Self.isValidKey(binding.key) else {
                    throw LinuxSettingsValidationError.invalidKey(action: action.rawValue, index: index, key: binding.key)
                }
                let modifiers = binding.modifiers.map(LinuxHotkeyBinding.normalizedModifier)
                for modifier in modifiers {
                    guard allowedModifiers.contains(modifier) else {
                        throw LinuxSettingsValidationError.invalidModifier(action: action.rawValue, index: index, modifier: modifier)
                    }
                }
                guard Set(modifiers).count == modifiers.count else {
                    throw LinuxSettingsValidationError.invalidModifier(action: action.rawValue, index: index, modifier: "duplicate")
                }
                let canonical = LinuxHotkeyBinding(key: binding.key, modifiers: modifiers)
                let identity = canonical.key.lowercased() + "|" + modifiers.sorted().joined(separator: ",")
                if let previous = seen[identity] {
                    throw LinuxSettingsValidationError.duplicateShortcut(firstAction: previous.action, secondAction: action.rawValue,
                                                                         key: canonical.key, modifiers: modifiers)
                }
                seen[identity] = (action.rawValue, canonical)
                bindings[index] = canonical
            }
            result.hotkeys[action.rawValue] = bindings
        }
        return result
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if key.count == 1 {
            return key.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && !scalar.properties.isWhitespace && scalar.value >= 0x20 && scalar.value != 0x7f
            }
        }
        if key.range(of: #"^F([1-9]|[12][0-9]|3[0-5])$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let names = Set(["escape", "esc", "return", "enter", "space", "tab", "back_space", "backspace", "delete", "insert", "home", "end", "page_up", "page_down", "left", "right", "up", "down", "print", "menu", "pause", "scroll_lock", "caps_lock", "num_lock", "super_l", "super_r", "alt_l", "alt_r", "control_l", "control_r", "shift_l", "shift_r", "iso_left_tab", "plus", "minus", "equal", "comma", "period", "slash", "semicolon", "apostrophe", "bracketleft", "bracketright", "backslash", "grave", "kp_enter", "kp_add", "kp_add", "kp_subtract", "kp_multiply", "kp_divide", "kp_decimal", "kp_separator", "kp_0", "kp_1", "kp_2", "kp_3", "kp_4", "kp_5", "kp_6", "kp_7", "kp_8", "kp_9"])
        if names.contains(key.lowercased()) { return true }
        return key.lowercased().hasPrefix("xf86") && key.dropFirst(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private enum CodingKeys: String, CodingKey { case capture, ocr, hotkeys, startHidden, launchAtLogin }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(capture: try values.decodeIfPresent(LinuxCaptureSettings.self, forKey: .capture) ?? LinuxCaptureSettings(),
                  ocr: try values.decodeIfPresent(LinuxOCRSettings.self, forKey: .ocr) ?? LinuxOCRSettings(),
                  hotkeys: try values.decodeIfPresent([String: [LinuxHotkeyBinding]].self, forKey: .hotkeys) ?? Self.defaultHotkeys,
                  startHidden: try values.decodeIfPresent(Bool.self, forKey: .startHidden) ?? false,
                  launchAtLogin: try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false)
    }
}

public struct LinuxCaptureRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let mode: LinuxCaptureMode
    public let path: String
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let applicationName: String?
    public let captureSettings: CaptureSettings?
    public let displayCount: Int?

    public var fileURL: URL { URL(fileURLWithPath: path) }

    public init(id: UUID = UUID(), timestamp: Date = Date(), mode: LinuxCaptureMode, path: String,
                width: Int, height: Int, windowTitle: String? = nil, applicationName: String? = nil,
                captureSettings: CaptureSettings? = nil, displayCount: Int? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.path = path
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.applicationName = applicationName
        self.captureSettings = captureSettings
        self.displayCount = displayCount
    }
}

public struct LinuxScreenshotHistoryEntry: Identifiable, Equatable, Sendable {
    public let record: LinuxCaptureRecord
    public let isMissing: Bool
    public var id: UUID { record.id }

    public init(record: LinuxCaptureRecord, isMissing: Bool) {
        self.record = record
        self.isMissing = isMissing
    }
}

public struct LinuxImageSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct LinuxCapturedImage: Sendable {
    public let path: URL
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let applicationName: String?
    public let displayCount: Int?

    public init(path: URL, width: Int, height: Int, windowTitle: String? = nil,
                applicationName: String? = nil, displayCount: Int? = nil) {
        self.path = path
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.applicationName = applicationName
        self.displayCount = displayCount
    }
}

public enum LinuxSupportError: Error, LocalizedError, Equatable, Sendable {
    case missingExecutable(String, installHint: String)
    case unsupported(String)
    case invalidOutput(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .missingExecutable(name, installHint):
            return "ShareX needs \(name) for this desktop action. Install it with \(installHint)."
        case let .unsupported(message), let .invalidOutput(message), let .processFailed(message):
            return message
        }
    }
}
