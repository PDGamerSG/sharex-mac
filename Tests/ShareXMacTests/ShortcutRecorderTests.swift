import AppKit
import ShareXMacCore
import Testing
@testable import ShareXMac

@Suite("Shortcut recorder")
@MainActor struct ShortcutRecorderTests {
    @Test("Option-F9 in media mode finishes recording and publishes the shortcut")
    func recordsMediaF9() throws {
        _ = NSApplication.shared
        let window = RecorderTestWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let button = ShortcutRecorderButton()
        window.contentView = button
        defer { button.finishRecording(); window.contentView = nil }
        var captured: [HotkeyBinding] = []
        var recordingChanges: [Bool] = []
        button.onChange = { captured.append($0) }
        button.onRecordingChange = { recordingChanges.append($0) }
        button.startRecording()
        #expect(recordingChanges == [true])
        let event = try #require(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [.option], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, subtype: 8, data1: 17 << 16 | 0xA00, data2: -1))
        NSApplication.shared.sendEvent(event)
        #expect(recordingChanges == [true, false])
        let binding = try #require(captured.first)
        #expect(captured.count == 1)
        #expect(binding.displayName == "⌥F9")
        #expect(binding.mediaKeyCode == 17)
        #expect(!button.record(event))
    }
}

// Keep the recorder's focus guard active without displaying a window or stealing user focus.
@MainActor private final class RecorderTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
