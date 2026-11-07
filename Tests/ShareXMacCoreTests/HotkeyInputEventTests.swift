import AppKit
import Testing
@testable import ShareXMacCore

@Suite("Shortcut input events")
@MainActor struct HotkeyInputEventTests {
    @Test("Option-F9 media events record a persistent shortcut without Fn")
    func recordsMediaF9() throws {
        let event = try mediaEvent(code: 17, flags: [.option])
        let binding = try #require(HotkeyBinding(recording: event))
        #expect(binding.keyCode == 101)
        #expect(binding.modifierFlags == 2048)
        #expect(binding.mediaKeyCode == 17)
        #expect(binding.displayName == "⌥F9")
        try HotkeyBinding.validate([.region: binding])
        #expect(throws: HotkeyValidationError.duplicate(.region, .ocrRegion)) {
            try HotkeyBinding.validate([.region: binding,
                                        .ocrRegion: HotkeyBinding(key: "F9", modifiers: ["option"])])
        }
    }

    @Test("normal F9 ignores Fn and Caps Lock when recording")
    func recordsStandardF9() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.option, .function, .capsLock], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 101))
        let binding = try #require(HotkeyBinding(recording: event))
        #expect(binding == HotkeyBinding(key: "F9", modifiers: ["option"]))
    }

    @Test("media releases, repeats, unrelated system events and unsupported keys do not record")
    func ignoresOtherEvents() throws {
        for event in [try mediaEvent(code: 17, down: false),
                      try mediaEvent(code: 17, repeatKey: true),
                      try mediaEvent(code: 17, subtype: 7),
                      try mediaEvent(code: 14)] {
            #expect(HotkeyBinding(recording: event) == nil)
        }
    }

    @Test("media shortcuts dispatch once, consume their release, and leave other keys alone")
    func mediaDispatch() throws {
        let binding = try #require(HotkeyBinding(recording: mediaEvent(code: 17, flags: [.option])))
        var matcher = MediaHotkeyMatcher(bindings: [2: binding])
        #expect(matcher.handle(try mediaEvent(code: 17)) == .passThrough)
        #expect(matcher.handle(try mediaEvent(code: 18, flags: [.option])) == .passThrough)
        #expect(matcher.handle(try mediaEvent(code: 17, flags: [.option, .shift])) == .passThrough)
        #expect(matcher.handle(try mediaEvent(code: 17, flags: [.option])) == .trigger(2))
        #expect(matcher.handle(try mediaEvent(code: 17, flags: [.option], repeatKey: true)) == .consumed)
        // Modifiers can be released before the media key itself.
        #expect(matcher.handle(try mediaEvent(code: 17, down: false)) == .consumed)
        #expect(matcher.handle(try mediaEvent(code: 17, down: false)) == .passThrough)
        #expect(matcher.handle(try mediaEvent(code: 17, flags: [.option])) == .trigger(2))
        matcher = MediaHotkeyMatcher()
        #expect(matcher.handle(try mediaEvent(code: 17, flags: [.option])) == .passThrough)
    }

    private func mediaEvent(code: Int, flags: NSEvent.ModifierFlags = [], down: Bool = true,
                            repeatKey: Bool = false, subtype: Int16 = 8) throws -> NSEvent {
        try #require(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            subtype: subtype, data1: code << 16 | (down ? 0xA00 : 0xB00) | (repeatKey ? 1 : 0), data2: -1))
    }
}
