import Foundation

public enum HotkeyValidationError: Error, Equatable, LocalizedError {
    case duplicate(HotkeyAction, HotkeyAction)
    case invalid(HotkeyAction)

    public var errorDescription: String? {
        switch self {
        case let .duplicate(first, second):
            return "\(first.title) and \(second.title) use the same shortcut. Choose a different combination."
        case let .invalid(action):
            return "Choose a key with Command, Control, or Option for \(action.title)."
        }
    }
}

/// Stores physical Carbon key codes. The string initializer and legacy JSON remain supported.
public struct HotkeyBinding: Codable, Equatable, Sendable {
    public private(set) var keyCode: UInt32?
    public private(set) var modifierFlags: UInt32
    private var unknownKey: String?
    private var unknownModifiers: [String] = []

    public var key: String {
        get { keyCode.map { Self.keyNames[$0] ?? "Key \($0)" } ?? unknownKey ?? "" }
        set {
            keyCode = Self.code(for: newValue)
            unknownKey = keyCode == nil && !newValue.isEmpty ? newValue : nil
        }
    }

    public var modifiers: [String] {
        get {
            Self.modifierNames.compactMap { modifierFlags & $0.flag != 0 ? $0.name : nil } + unknownModifiers
        }
        set {
            modifierFlags = 0
            unknownModifiers = []
            for name in newValue {
                switch name.lowercased() {
                case "command", "cmd", "⌘": modifierFlags |= 256
                case "shift", "⇧": modifierFlags |= 512
                case "option", "alt", "⌥": modifierFlags |= 2048
                case "control", "ctrl", "⌃": modifierFlags |= 4096
                default: unknownModifiers.append(name)
                }
            }
        }
    }

    public init(key: String = "", modifiers: [String] = []) {
        keyCode = nil
        modifierFlags = 0
        self.key = key
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public var isEmpty: Bool { keyCode == nil && unknownKey == nil && modifierFlags == 0 && unknownModifiers.isEmpty }

    public var displayName: String {
        guard !isEmpty else { return "Record shortcut" }
        let symbols = [(UInt32(4096), "⌃"), (2048, "⌥"), (512, "⇧"), (256, "⌘")]
            .filter { modifierFlags & $0.0 != 0 }.map(\.1).joined()
        return symbols + key.uppercased()
    }

    public static func validate(_ bindings: [HotkeyAction: HotkeyBinding]) throws {
        var seen: [UInt64: HotkeyAction] = [:]
        for action in HotkeyAction.allCases {
            guard let binding = bindings[action], !binding.isEmpty else { continue }
            guard let code = binding.keyCode, code <= 127,
                  ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code),
                  binding.modifierFlags & ~UInt32(6912) == 0,
                  binding.modifierFlags & UInt32(6400) != 0,
                  binding.unknownModifiers.isEmpty else {
                throw HotkeyValidationError.invalid(action)
            }
            let identity = UInt64(code) << 32 | UInt64(binding.modifierFlags)
            if let other = seen[identity] { throw HotkeyValidationError.duplicate(other, action) }
            seen[identity] = action
        }
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifierFlags, key, modifiers }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.keyCode) || values.contains(.modifierFlags) {
            self.init()
            keyCode = try values.decodeIfPresent(UInt32.self, forKey: .keyCode)
            modifierFlags = try values.decodeIfPresent(UInt32.self, forKey: .modifierFlags) ?? 0
            unknownKey = try values.decodeIfPresent(String.self, forKey: .key)
            if keyCode != nil || unknownKey?.isEmpty == true { unknownKey = nil }
            // Preserve malformed legacy values on a round trip so validation still rejects them.
            unknownModifiers = try values.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        } else {
            self.init(key: try values.decode(String.self, forKey: .key),
                      modifiers: try values.decode([String].self, forKey: .modifiers))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(keyCode, forKey: .keyCode)
        try values.encode(modifierFlags, forKey: .modifierFlags)
        try values.encodeIfPresent(unknownKey, forKey: .key)
        if !unknownModifiers.isEmpty { try values.encode(unknownModifiers, forKey: .modifiers) }
    }

    private static let modifierNames: [(flag: UInt32, name: String)] = [(256, "command"), (512, "shift"), (2048, "option"), (4096, "control")]

    private static func code(for key: String) -> UInt32? {
        let name = key.lowercased()
        let aliases = ["return": "↩", "enter": "↩", "escape": "⎋", "esc": "⎋", "space": "space", " ": "space", "tab": "⇥", "delete": "⌫", "backspace": "⌫", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return keyNames.first { $0.value.lowercased() == (aliases[name] ?? name) }?.key
    }

    // ANSI positions are stable; persisted shortcuts use codes rather than localized characters.
    private static let keyNames: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 10: "§", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        36: "↩", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".",
        48: "⇥", 49: "space", 50: "`", 51: "⌫", 53: "⎋", 64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +",
        71: "Clear", 75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6",
        89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home",
        116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

public extension HotkeyAction {
    var title: String {
        switch self {
        case .fullscreen: "Full-screen capture"
        case .region: "Region capture"
        case .window: "Window capture"
        case .ocrRegion: "OCR region capture"
        case .history: "History"
        case .imageHistory: "Image history"
        case .settings: "Settings"
        }
    }
}
