import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Hotkey bindings")
struct HotkeyBindingTests {
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

    @Test("clearing and resetting remove active bindings and permit reusing a shortcut")
    func clearAndReset() throws {
        var settings = AppSettings()
        settings.hotkeys[.fullscreen] = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        settings.hotkeys[.fullscreen] = HotkeyBinding()
        settings.hotkeys[.region] = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        try HotkeyBinding.validate(settings.hotkeys)
        #expect(settings.hotkeys[.fullscreen]?.isEmpty == true)
        settings.hotkeys = AppSettings.defaultHotkeys
        try HotkeyBinding.validate(settings.hotkeys)
        let allEmpty = settings.hotkeys.values.allSatisfy { $0.isEmpty }
        #expect(allEmpty)
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

    @Test("plain typing, unknown modifiers and invalid keycodes are rejected")
    func invalidBindings() {
        for binding in [HotkeyBinding(keyCode: 40, modifierFlags: 0),
                        HotkeyBinding(keyCode: 40, modifierFlags: 512),
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
