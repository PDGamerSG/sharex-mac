import AppKit

@MainActor
final class CaptureCountdown: NSObject {
    private var panel: NSPanel?
    private var cancel: (() -> Void)?

    func wait(seconds: Double, onCancel: @escaping () -> Void) async throws {
        guard seconds > 0 else { return }
        cancel = onCancel
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 118),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Screenshot Delay"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        label.setAccessibilityLabel("Seconds until screenshot")
        let button = NSButton(title: "Cancel", target: self, action: #selector(cancelCapture))
        button.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                                         stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        }
        panel.center()
        self.panel = panel
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
            self.panel = nil
            cancel = nil
        }
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while true {
            try Task.checkCancellation()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { break }
            label.stringValue = "Capturing in \(Int(ceil(remaining)))…"
            try await Task.sleep(nanoseconds: UInt64(min(remaining, 0.1) * 1_000_000_000))
        }
    }

    func close() { panel?.orderOut(nil) }
    @objc private func cancelCapture() { cancel?() }
}
