import AppKit

public extension HotkeyBinding {
    /// Converts an initial key press, including Apple's media-mode top row, into a binding.
    init?(recording event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            self.init(keyCode: UInt32(event.keyCode), modifierFlags: Self.carbonModifiers(event.modifierFlags))
        } else if let media = MediaKeyEvent(event), media.isDown, !media.isRepeat {
            self.init(keyCode: media.functionKeyCode, modifierFlags: media.modifierFlags, mediaKeyCode: media.code)
        } else {
            return nil
        }
    }

    internal static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= 256 }
        if flags.contains(.shift) { result |= 512 }
        if flags.contains(.option) { result |= 2048 }
        if flags.contains(.control) { result |= 4096 }
        return result
    }
}

struct MediaKeyEvent {
    let code: UInt32
    let functionKeyCode: UInt32
    let modifierFlags: UInt32
    let isDown: Bool
    let isRepeat: Bool

    init?(_ event: NSEvent) {
        // NX_SUBTYPE_AUX_CONTROL_BUTTONS carries NX_KEYTYPE_* and a down/up state.
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let data = UInt32(truncatingIfNeeded: event.data1)
        let code = data >> 16
        let state = (data >> 8) & 0xFF
        guard let functionKeyCode = HotkeyBinding.functionKeyCode(forMediaKeyCode: code),
              state == 0xA || state == 0xB else { return nil }
        self.code = code
        self.functionKeyCode = functionKeyCode
        modifierFlags = HotkeyBinding.carbonModifiers(event.modifierFlags)
        isDown = state == 0xA
        isRepeat = data & 1 != 0
    }
}

struct MediaHotkeyMatcher {
    enum Result: Equatable {
        case passThrough
        case consumed
        case trigger(UInt32)
    }

    var bindings: [UInt32: HotkeyBinding] = [:]
    private var pressedKeys: Set<UInt32> = []

    init(bindings: [UInt32: HotkeyBinding] = [:]) { self.bindings = bindings }

    mutating func handle(_ event: NSEvent) -> Result {
        guard let media = MediaKeyEvent(event) else { return .passThrough }
        if pressedKeys.contains(media.functionKeyCode) {
            if !media.isDown { pressedKeys.remove(media.functionKeyCode) }
            return .consumed
        }
        guard media.isDown,
              let (id, _) = bindings.first(where: {
                  $0.value.mediaKeyCode != nil && $0.value.keyCode == media.functionKeyCode
                      && $0.value.modifierFlags == media.modifierFlags
              }) else { return .passThrough }
        pressedKeys.insert(media.functionKeyCode)
        return media.isRepeat ? .consumed : .trigger(id)
    }
}
