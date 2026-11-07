import AppKit
import SwiftUI
import ShareXMacCore

@MainActor
struct HotkeySettingsView: View {
    @ObservedObject var settingsModel: SettingsViewModel
    @ObservedObject var manager: GlobalHotkeyManager
    @ViewState private var validationError: String? = nil

    var body: some View {
        Form {
            Section {
                Text("Choose a row, then press a single key or a combination with Command, Control, Option, or Shift. Escape cancels recording; Delete clears it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Function keys also work when your top row controls media or brightness. Record the keys exactly as you will use them. Allow Accessibility access if a media-key shortcut reports a permission error. Holding Fn records the standard function key instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Capture") {
                ForEach([HotkeyAction.fullscreen, .region, .window, .ocrRegion], id: \.self) { action in
                    shortcutRow(for: action)
                }
            }
            Section("App navigation") {
                ForEach([HotkeyAction.imageHistory, .settings], id: \.self) { action in
                    shortcutRow(for: action)
                }
            }
            Section {
                Button("Reset all shortcuts", role: .destructive) {
                    if settingsModel.update({ $0.hotkeys = AppSettings.defaultHotkeys }) {
                        validationError = nil
                        restoreRegistrations()
                    }
                }
                .controlSize(.small)
                Text("Defaults: Option-P captures a region; Shift-P recognizes text in a region. Other shortcuts are unassigned. A shortcut that conflicts with another action or macOS is called out below its row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let validationError {
                Section {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Shortcut error: \(validationError)")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func shortcutRow(for action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(action.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HotkeyRecorder(binding: settingsModel.settings.hotkeys[action] ?? HotkeyBinding(),
                               label: action.title,
                               onChange: { update(action, binding: $0) },
                               onRecordingChange: recordingChanged)
                    .frame(width: 170, height: 28)
                Button {
                    update(action, binding: HotkeyBinding())
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(settingsModel.settings.hotkeys[action]?.isEmpty ?? true)
                .help("Clear \(action.title) shortcut")
                .accessibilityLabel("Clear \(action.title) shortcut")
            }
            if let message = manager.registrationErrors[action] {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                if settingsModel.settings.hotkeys[action]?.mediaKeyCode != nil {
                    Button("Open Accessibility settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
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
        button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
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
final class ShortcutRecorderButton: NSButton {
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.recording, self.window?.isKeyWindow == true else { return false }
                return self.record(event)
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
        _ = record(event)
    }

    @discardableResult
    func record(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.type == .systemDefined {
            guard let captured = HotkeyBinding(recording: event) else { return false }
            finishRecording()
            onChange?(captured)
            return true
        }
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 { finishRecording(); return true }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let result: HotkeyBinding
        if (event.keyCode == 51 || event.keyCode == 117) && flags.isEmpty {
            result = HotkeyBinding()
        } else {
            guard let captured = HotkeyBinding(recording: event) else { return true }
            result = captured
        }
        finishRecording()
        onChange?(result)
        return true
    }
}
