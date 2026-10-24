import AppKit
import ShareXMacCore

@MainActor
final class CaptureConfirmation: NSObject {
    private var panel: NSPanel?
    private var displayTask: Task<Void, Never>?
    private var currentRecord: CaptureRecord?

    func show(record: CaptureRecord) {
        displayTask?.cancel()
        panel?.orderOut(nil)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 76),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
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

        let openFolder = NSButton(title: "Open Folder", target: self, action: #selector(openFolder(_:)))
        openFolder.bezelStyle = .rounded
        openFolder.controlSize = .small
        openFolder.toolTip = "Open the folder containing this screenshot"
        openFolder.setAccessibilityLabel("Open screenshot folder")
        openFolder.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(icon)
        effect.addSubview(labels)
        effect.addSubview(openFolder)
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
                labels.trailingAnchor.constraint(lessThanOrEqualTo: openFolder.leadingAnchor, constant: -10),
                labels.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
                openFolder.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
                openFolder.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
            ])
        }

        currentRecord = record
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
        currentRecord = nil
    }

    @objc private func openFolder(_ sender: NSButton) {
        guard let record = currentRecord else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
        close()
    }
}
