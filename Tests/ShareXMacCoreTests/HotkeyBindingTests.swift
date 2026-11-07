import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Hotkey bindings")
struct HotkeyBindingTests {
    @Test("media-mode Option-F9 keeps its event identity when saved")
    func mediaShortcutPersistence() throws {
        let binding = try JSONDecoder().decode(HotkeyBinding.self, from: Data(
            #"{"keyCode":101,"modifierFlags":2048,"mediaKeyCode":17}"#.utf8))
        try HotkeyBinding.validate([.region: binding])
        #expect(binding.displayName == "⌥F9")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any]
        #expect(encoded?["mediaKeyCode"] as? Int == 17)
    }

    @Test("malformed media bindings are rejected")
    func invalidMediaShortcuts() throws {
        for json in [#"{"keyCode":101,"modifierFlags":2048,"mediaKeyCode":999}"#,
                     #"{"keyCode":35,"modifierFlags":2048,"mediaKeyCode":17}"#,
                     #"{"modifierFlags":0,"mediaKeyCode":17}"#] {
            let binding = try JSONDecoder().decode(HotkeyBinding.self, from: Data(json.utf8))
            #expect(throws: HotkeyValidationError.self) {
                try HotkeyBinding.validate([.region: binding])
            }
        }
    }

    @Test("new keycode settings decode without losing the physical key")
    func modernSettingsDecode() throws {
        let data = Data(#"{"keyCode":40,"modifierFlags":2304}"#.utf8)
        let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        #expect(binding != nil)
        #expect(binding?.key.lowercased() == "k")
        #expect(binding?.modifiers.contains("command") == true)
        #expect(binding?.modifiers.contains("option") == true)
    }

    @Test("legacy modifier aliases migrate and collide with a physical shortcut")
    func legacyMigrationAndDuplicates() throws {
        let legacy = try JSONDecoder().decode(HotkeyBinding.self, from: Data(#"{"key":"K","modifiers":["cmd","alt"]}"#.utf8))
        #expect(legacy.keyCode == 40)
        #expect(legacy.modifierFlags == 2304)
        #expect(throws: HotkeyValidationError.duplicate(.fullscreen, .region)) {
            try HotkeyBinding.validate([.fullscreen: legacy, .region: HotkeyBinding(keyCode: 40, modifierFlags: 2304)])
        }
    }

    @Test("clearing and resetting release custom shortcuts for reuse")
    func clearAndReset() throws {
        var settings = AppSettings()
        settings.hotkeys[.fullscreen] = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        settings.hotkeys[.fullscreen] = HotkeyBinding()
        settings.hotkeys[.region] = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        try HotkeyBinding.validate(settings.hotkeys)
        #expect(settings.hotkeys[.fullscreen]?.isEmpty == true)
        settings.hotkeys = AppSettings.defaultHotkeys
        settings.hotkeys[.fullscreen] = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        try HotkeyBinding.validate(settings.hotkeys)
    }

    @Test("physical key zero remains bound and round trips alongside legacy settings")
    func stableCodable() throws {
        var settings = AppSettings()
        settings.hotkeys[.fullscreen] = HotkeyBinding(keyCode: 0, modifierFlags: 4352)
        settings.hotkeys[.region] = HotkeyBinding(key: "r", modifiers: ["control", "shift"])
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(restored == settings)
        #expect(restored.hotkeys[.fullscreen]?.isEmpty == false)
        #expect(restored.hotkeys[.fullscreen]?.keyCode == 0)
        #expect(restored.hotkeys[.region]?.keyCode == 15)
        #expect(restored.hotkeys[.region]?.modifierFlags == 4608)
    }

    @Test("Shift-only OCR shortcuts validate and survive saving", arguments: ["p", "b"])
    func shiftOnlyShortcuts(key: String) throws {
        let binding = HotkeyBinding(key: key, modifiers: ["shift"])
        let restored = try JSONDecoder().decode(HotkeyBinding.self, from: JSONEncoder().encode(binding))
        try HotkeyBinding.validate([.ocrRegion: restored,
                                    .region: HotkeyBinding(key: "b", modifiers: ["option"])])
        #expect(restored.modifierFlags == 512)
        #expect(restored.displayName == "⇧\(key.uppercased())")
        #expect(throws: HotkeyValidationError.duplicate(.region, .ocrRegion)) {
            try HotkeyBinding.validate([.region: restored, .ocrRegion: restored])
        }
    }

    @Test("single keys and Option-F9 validate, persist and detect duplicates",
          arguments: [HotkeyBinding(key: "a"), HotkeyBinding(key: "p"),
                      HotkeyBinding(key: "F9"), HotkeyBinding(key: "F9", modifiers: ["option"])])
    func singleKeysAndFunctionKeys(binding: HotkeyBinding) throws {
        let restored = try JSONDecoder().decode(HotkeyBinding.self, from: JSONEncoder().encode(binding))
        try HotkeyBinding.validate([.region: restored])
        #expect(restored == binding)
        #expect(!restored.isEmpty)
        #expect(throws: HotkeyValidationError.duplicate(.region, .ocrRegion)) {
            try HotkeyBinding.validate([.region: restored, .ocrRegion: restored])
        }
    }

    @Test("modifier-only keys, unknown modifiers and invalid keycodes are rejected")
    func invalidBindings() {
        for binding in [HotkeyBinding(keyCode: 56, modifierFlags: 512),
                        HotkeyBinding(keyCode: 40, modifierFlags: 1024),
                        HotkeyBinding(keyCode: 65535, modifierFlags: 256),
                        HotkeyBinding(key: "not a key", modifiers: ["command"]),
                        HotkeyBinding(key: "k", modifiers: ["command", "hyper"]),
                        HotkeyBinding(keyCode: 40, modifierFlags: 1 << 20)] {
            #expect(throws: HotkeyValidationError.self) {
                try HotkeyBinding.validate([.settings: binding])
            }
        }
    }

}
