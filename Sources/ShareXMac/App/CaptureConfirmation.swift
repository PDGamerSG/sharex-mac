import AppKit
import ShareXMacCore

@MainActor
final class CaptureConfirmation {
    private var panel: NSPanel?
    private var displayTask: Task<Void, Never>?

    func show(record: CaptureRecord) {
        displayTask?.cancel()
        panel?.orderOut(nil)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 292, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Screenshot taken")!)
        icon.contentTintColor = .systemGreen
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Screenshot taken")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: URL(fileURLWithPath: record.path).lastPathComponent)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(icon)
        effect.addSubview(labels)
        panel.contentView?.addSubview(effect)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                effect.topAnchor.constraint(equalTo: content.topAnchor),
                effect.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
                icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28),
                labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                labels.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
                labels.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
            ])
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 18,
                                     y: frame.minY + 18))
        self.panel = panel
        panel.orderFrontRegardless()

        displayTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }

    func close() {
        displayTask?.cancel()
        displayTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
