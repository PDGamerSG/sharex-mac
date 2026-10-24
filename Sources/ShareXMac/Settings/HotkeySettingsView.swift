import AppKit
import SwiftUI
import ShareXMacCore

@MainActor
struct HotkeySettingsView: View {
    @ObservedObject var settingsModel: SettingsViewModel
    @ObservedObject var manager: GlobalHotkeyManager
    @ViewState private var validationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click a shortcut, then press a key with Command, Control, or Option. Escape cancels; Delete clears.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(action.title)
                        Spacer()
                        HotkeyRecorder(binding: settingsModel.settings.hotkeys[action] ?? HotkeyBinding(),
                                       label: action.title,
                                       onChange: { update(action, binding: $0) },
                                       onRecordingChange: recordingChanged)
                            .frame(width: 170, height: 28)
                        Button("Clear") { update(action, binding: HotkeyBinding()) }
                            .disabled(settingsModel.settings.hotkeys[action]?.isEmpty ?? true)
                            .accessibilityLabel("Clear \(action.title) shortcut")
                    }
                    if let message = manager.registrationErrors[action] {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            if let validationError {
                Text(validationError).font(.callout).foregroundStyle(.red)
                    .accessibilityLabel("Shortcut error: \(validationError)")
            }
            HStack {
                Button("Reset Shortcuts") {
                    if settingsModel.update({ $0.hotkeys = AppSettings.defaultHotkeys }) {
                        validationError = nil
                        restoreRegistrations()
                    }
                }
                Text("Defaults are unassigned. Reset clears all seven shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func update(_ action: HotkeyAction, binding: HotkeyBinding) {
        var candidate = settingsModel.settings.hotkeys
        candidate[action] = binding
        do {
            try HotkeyBinding.validate(candidate)
            if settingsModel.update({ $0.hotkeys = candidate }) {
                validationError = nil
                restoreRegistrations()
            }
        } catch { validationError = error.localizedDescription }
    }

    private func recordingChanged(_ recording: Bool) {
        // Temporarily release shortcuts so recording an existing combination never launches it.
        if recording { manager.unregisterAll() } else { restoreRegistrations() }
    }

    private func restoreRegistrations() {
        do { try manager.register(settingsModel.settings.hotkeys) }
        catch { validationError = error.localizedDescription }
    }
}

@MainActor
private struct HotkeyRecorder: NSViewRepresentable {
    let binding: HotkeyBinding
    let label: String
    let onChange: (HotkeyBinding) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.binding = binding
        button.onChange = onChange
        button.onRecordingChange = onRecordingChange
        button.setAccessibilityLabel("\(label) shortcut")
        button.setAccessibilityHelp("Press to record a shortcut. Escape cancels; Delete clears.")
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.finishRecording()
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var binding = HotkeyBinding()
    var onChange: ((HotkeyBinding) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var recording = false
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    @objc func startRecording() {
        guard !recording, window?.makeFirstResponder(self) == true else { return }
        recording = true
        onRecordingChange?(true)
        // This monitor sees only this app's events; it consumes menu equivalents while recording.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.recording, self.window?.isKeyWindow == true else { return false }
                self.keyDown(with: event)
                return true
            }
            return consumed ? nil : event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowResigned),
                                               name: NSWindow.didResignKeyNotification, object: window)
        refreshTitle()
    }

    func refreshTitle() {
        title = recording ? "Type shortcut…" : binding.displayName
    }

    func finishRecording() {
        guard recording else { return }
        recording = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        refreshTitle()
        onRecordingChange?(false)
    }

    @objc private func windowResigned(_ notification: Notification) { finishRecording() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishRecording() }
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finishRecording(); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let result: HotkeyBinding
        if (event.keyCode == 51 || event.keyCode == 117) && flags.isEmpty {
            result = HotkeyBinding()
        } else {
            var carbon: UInt32 = 0
            if flags.contains(.command) { carbon |= 256 }
            if flags.contains(.shift) { carbon |= 512 }
            if flags.contains(.option) { carbon |= 2048 }
            if flags.contains(.control) { carbon |= 4096 }
            result = HotkeyBinding(keyCode: UInt32(event.keyCode), modifierFlags: carbon)
        }
        finishRecording()
        onChange?(result)
    }
}
