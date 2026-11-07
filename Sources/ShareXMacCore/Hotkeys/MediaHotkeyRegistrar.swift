import AppKit

/// Intercepts only system-defined media events. Ordinary shortcuts still use Carbon.
@MainActor
final class MediaHotkeyRegistrar {
    var onHotkey: (@MainActor (UInt32) -> Void)?
    private var matcher = MediaHotkeyMatcher()
    private let resources = MediaHotkeyResources()

    func register(id: UInt32, binding: HotkeyBinding) throws {
        if resources.tap == nil {
            let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let consumed = MainActor.assumeIsolated {
                        let registrar = Unmanaged<MediaHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let tap = registrar.resources.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                            return false
                        }
                        guard let input = NSEvent(cgEvent: event) else { return false }
                        switch registrar.matcher.handle(input) {
                        case .passThrough: return false
                        case .consumed: return true
                        case let .trigger(id):
                            registrar.onHotkey?(id)
                            return true
                        }
                    }
                    return consumed ? nil : Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                throw MediaHotkeyError()
            }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CFMachPortInvalidate(tap)
                throw MediaHotkeyError()
            }
            resources.tap = tap
            resources.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        matcher.bindings[id] = binding
    }

    func unregisterAll() {
        matcher = MediaHotkeyMatcher()
        resources.unregisterAll()
    }
}

private final class MediaHotkeyResources: @unchecked Sendable {
    var tap: CFMachPort?
    var source: CFRunLoopSource?

    func unregisterAll() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    deinit { unregisterAll() }
}

private struct MediaHotkeyError: LocalizedError {
    var errorDescription: String? {
        "To use a media-mode function key, allow ShareX Mac in System Settings → Privacy & Security → Accessibility, then record the shortcut again. You can also record it with Fn held."
    }
}
