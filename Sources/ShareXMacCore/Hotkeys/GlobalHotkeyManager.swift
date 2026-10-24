import Carbon
import Combine
import Foundation

@MainActor
protocol HotkeyRegistering: AnyObject {
    var onHotkey: (@MainActor (UInt32) -> Void)? { get set }
    func register(id: UInt32, binding: HotkeyBinding) throws
    func unregisterAll()
}

@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    @Published public private(set) var registrationErrors: [HotkeyAction: String] = [:]
    public var registrationError: String? {
        let messages = HotkeyAction.allCases.compactMap { registrationErrors[$0] }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private let registrar: any HotkeyRegistering
    private let actionHandler: @MainActor (HotkeyAction) -> Void
    private var activeActions: [UInt32: HotkeyAction] = [:]

    public convenience init(actionHandler: @escaping @MainActor (HotkeyAction) -> Void) {
        self.init(registrar: CarbonHotkeyRegistrar(), actionHandler: actionHandler)
    }

    init(registrar: any HotkeyRegistering, actionHandler: @escaping @MainActor (HotkeyAction) -> Void) {
        self.registrar = registrar
        self.actionHandler = actionHandler
        registrar.onHotkey = { [weak self] id in
            guard let self, let action = self.activeActions[id] else { return }
            self.actionHandler(action)
        }
    }

    /// Invalid configurations leave working bindings intact. OS conflicts are reported per action.
    public func register(_ bindings: [HotkeyAction: HotkeyBinding]) throws {
        try HotkeyBinding.validate(bindings)
        unregisterAll()
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let binding = bindings[action], !binding.isEmpty else { continue }
            let id = UInt32(index + 1)
            do {
                try registrar.register(id: id, binding: binding)
                activeActions[id] = action
            } catch {
                registrationErrors[action] = "\(action.title): \(error.localizedDescription) Choose another shortcut or clear it."
            }
        }
    }

    public func unregisterAll() {
        activeActions.removeAll()
        registrar.unregisterAll()
        registrationErrors = [:]
    }
}

@MainActor
private final class CarbonHotkeyRegistrar: HotkeyRegistering {
    var onHotkey: (@MainActor (UInt32) -> Void)?
    private let resources = CarbonHotkeyResources()
    private static let signature: OSType = 0x53784D63 // SxMc

    func register(id: UInt32, binding: HotkeyBinding) throws {
        if resources.handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotkey = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
                guard result == noErr, hotkey.signature == 0x53784D63 else { return OSStatus(eventNotHandledErr) }
                let id = hotkey.id
                // Application event handlers run on the main event loop.
                return MainActor.assumeIsolated {
                    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                    registrar.onHotkey?(id)
                    return noErr
                }
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &resources.handler)
            guard status == noErr else { throw CarbonHotkeyError(status: status) }
        }
        guard let code = binding.keyCode else { return }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(code, binding.modifierFlags, EventHotKeyID(signature: Self.signature, id: id),
                                        GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { throw CarbonHotkeyError(status: status) }
        resources.registrations.append(reference)
    }

    func unregisterAll() { resources.unregisterAll() }
}

/// Carbon owns these handles until explicit unregister or final release. Access is serialized by
/// the main-actor registrar; final destruction has exclusive access and also releases the handles.
private final class CarbonHotkeyResources: @unchecked Sendable {
    var handler: EventHandlerRef?
    var registrations: [EventHotKeyRef] = []

    func unregisterAll() {
        for reference in registrations { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregisterAll() }
}

private struct CarbonHotkeyError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        if status == eventHotKeyExistsErr { return "This shortcut is already in use by macOS or another application." }
        return "macOS could not register this shortcut (error \(status))."
    }
}
