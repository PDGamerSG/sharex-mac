import Carbon
import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Global hotkey registration")
@MainActor struct GlobalHotkeyManagerTests {
    @Test("one system conflict preserves other actions and only active IDs dispatch")
    func partialFailure() throws {
        let registrar = TestHotkeyRegistrar()
        registrar.failedIDs = [1]
        var actions: [HotkeyAction] = []
        let manager = GlobalHotkeyManager(registrar: registrar, actionHandler: { actions.append($0) })
        try manager.register([.fullscreen: HotkeyBinding(keyCode: 40, modifierFlags: 2304),
                              .region: HotkeyBinding(keyCode: 15, modifierFlags: 2304)])
        #expect(manager.registrationErrors[.fullscreen] != nil)
        #expect(manager.registrationErrors[.region] == nil)
        registrar.onHotkey?(1)
        registrar.onHotkey?(2)
        registrar.onHotkey?(999)
        #expect(actions == [.region])
        manager.unregisterAll()
        registrar.onHotkey?(2)
        #expect(actions == [.region])
        #expect(manager.registrationError == nil)
    }

    @Test("invalid replacement preserves the working registration")
    func validationBeforeReplacement() throws {
        let registrar = TestHotkeyRegistrar()
        var actions: [HotkeyAction] = []
        let manager = GlobalHotkeyManager(registrar: registrar, actionHandler: { actions.append($0) })
        let binding = HotkeyBinding(keyCode: 40, modifierFlags: 2304)
        try manager.register([.region: binding])
        #expect(throws: HotkeyValidationError.self) {
            try manager.register([.fullscreen: binding, .region: binding])
        }
        registrar.onHotkey?(2)
        #expect(actions == [.region])
    }

    @Test("replacing, clearing and reset release old registrations and failures")
    func replaceAndClear() throws {
        let registrar = TestHotkeyRegistrar()
        registrar.failedIDs = [1]
        var actions: [HotkeyAction] = []
        let manager = GlobalHotkeyManager(registrar: registrar, actionHandler: { actions.append($0) })
        try manager.register([.fullscreen: HotkeyBinding(keyCode: 40, modifierFlags: 2304)])
        #expect(manager.registrationError != nil)
        registrar.failedIDs = []
        try manager.register([.settings: HotkeyBinding(keyCode: 15, modifierFlags: 2304)])
        #expect(manager.registrationErrors.isEmpty)
        registrar.onHotkey?(1)
        registrar.onHotkey?(6)
        #expect(actions == [.settings])
        try manager.register(AppSettings.defaultHotkeys)
        registrar.onHotkey?(6)
        #expect(actions == [.settings])
        #expect(registrar.activeIDs.isEmpty)
    }

    @Test("Carbon reports duplicate system registrations and dispatches an owned event")
    func nativeRegistration() throws {
        var actions: [HotkeyAction] = []
        let first = GlobalHotkeyManager(actionHandler: { actions.append($0) })
        let second = GlobalHotkeyManager(actionHandler: { _ in })
        defer { first.unregisterAll(); second.unregisterAll() }
        let binding = HotkeyBinding(keyCode: 80, modifierFlags: 6912)
        try first.register([.settings: binding])
        #expect(first.registrationErrors.isEmpty)
        try second.register([.imageHistory: binding])
        #expect(second.registrationErrors[.imageHistory] != nil)
        second.unregisterAll()

        var event: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                            GetCurrentEventTime(), 0, &event) == noErr)
        let created = try #require(event)
        defer { ReleaseEvent(created) }
        var identity = EventHotKeyID(signature: 0x53784D63, id: 6)
        #expect(SetEventParameter(created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &identity) == noErr)
        #expect(SendEventToEventTarget(created, GetApplicationEventTarget()) == noErr)
        #expect(actions == [.settings])
        first.unregisterAll()
        try second.register([.imageHistory: binding])
        #expect(second.registrationErrors.isEmpty)
    }

}

@MainActor private final class TestHotkeyRegistrar: HotkeyRegistering {
    var onHotkey: (@MainActor (UInt32) -> Void)?
    var failedIDs: Set<UInt32> = []
    var activeIDs: Set<UInt32> = []
    func register(id: UInt32, binding: HotkeyBinding) throws {
        if failedIDs.contains(id) { throw Conflict() }
        activeIDs.insert(id)
    }
    func unregisterAll() { activeIDs.removeAll() }
    private struct Conflict: Error {}
}
