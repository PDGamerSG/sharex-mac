import AppKit
@preconcurrency import ScreenCaptureKit
import ShareXMacCore

@MainActor
public final class WindowPickerPanel {
    public init() {}

    public func selectWindow() async throws -> SCWindow? {
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let orderedIDs = windowInfo.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let order = Dictionary(orderedIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let processID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows
            .filter { $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0 && $0.owningApplication?.processID != processID }
            .sorted { lhs, rhs in
                (order[lhs.windowID] ?? Int.max) < (order[rhs.windowID] ?? Int.max)
            }
        guard !windows.isEmpty else { throw ScreenCaptureService.CaptureError.noWindows }

        let bounds = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.isNull ? screen.frame : partial.union(screen.frame)
        }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let panel = SelectionPanelWindow(contentRect: bounds)
        let view = WindowPickerView(windows: windows, screenBounds: bounds)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)

        let result = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGWindowID?, Never>) in
                view.setContinuation(continuation)
            }
        }, onCancel: {
            Task { @MainActor in view.cancel() }
        })

        panel.orderOut(nil)
        return windows.first { $0.windowID == result }
    }
}

private final class WindowPickerView: NSView {
    private let windows: [SCWindow]
    private let screenBounds: CGRect
    private var hoveredWindow: SCWindow?
    private var continuation: CheckedContinuation<CGWindowID?, Never>?
    private var finished = false
    private var pendingResult: CGWindowID?

    init(windows: [SCWindow], screenBounds: CGRect) {
        self.windows = windows
        self.screenBounds = screenBounds
        super.init(frame: CGRect(origin: .zero, size: screenBounds.size))
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 1
        hoveredWindow = windows.first { appKitFrame(for: $0).contains(NSEvent.mouseLocation) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func setContinuation(_ continuation: CheckedContinuation<CGWindowID?, Never>) {
        guard !finished else {
            continuation.resume(returning: pendingResult)
            return
        }
        self.continuation = continuation
    }

    func cancel() {
        finish(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        guard let hoveredWindow,
              let rect = rectInView(for: hoveredWindow) else { return }
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        rect.fill()
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 3
        outline.stroke()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = screenPoint(for: event)
        let nextWindow = windows.first { appKitFrame(for: $0).contains(point) }
        if nextWindow?.windowID != hoveredWindow?.windowID {
            hoveredWindow = nextWindow
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(for: event)
        if let selected = windows.first(where: { appKitFrame(for: $0).contains(point) }) {
            finish(selected)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        finish(nil)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func appKitFrame(for window: SCWindow) -> CGRect {
        DesktopGeometry(quartzBounds: .zero, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
            .appKitRect(fromQuartz: window.frame)
    }

    private func rectInView(for window: SCWindow) -> CGRect? {
        let frame = appKitFrame(for: window).intersection(screenBounds)
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        return CGRect(x: frame.minX - screenBounds.minX,
                      y: frame.minY - screenBounds.minY,
                      width: frame.width,
                      height: frame.height)
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    private func finish(_ result: SCWindow?) {
        guard !finished else { return }
        finished = true
        pendingResult = result?.windowID
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: pendingResult)
    }
}

