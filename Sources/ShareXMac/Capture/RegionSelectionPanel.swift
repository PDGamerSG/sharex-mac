import AppKit
import CoreGraphics
import ShareXMacCore

@MainActor
public final class RegionSelectionPanel {
    public init() {}

    public func select(image: CGImage, screenBounds: CGRect) async -> CGRect? {
        guard !Task.isCancelled, screenBounds.width > 0, screenBounds.height > 0 else { return nil }

        let panel = SelectionPanelWindow(contentRect: screenBounds)
        let view = RegionSelectionView(image: image, screenBounds: screenBounds)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)

        let result = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGRect?, Never>) in
                view.setContinuation(continuation)
            }
        }, onCancel: {
            Task { @MainActor in view.cancel() }
        })

        panel.orderOut(nil)
        return result
    }
}

private final class RegionSelectionView: NSView {
    private let image: NSImage
    private let screenBounds: CGRect
    private let model = RegionSelectionModel()
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var finished = false
    private var pendingResult: CGRect?

    init(image: CGImage, screenBounds: CGRect) {
        self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        self.screenBounds = screenBounds
        super.init(frame: CGRect(origin: .zero, size: screenBounds.size))
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func setContinuation(_ continuation: CheckedContinuation<CGRect?, Never>) {
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
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        guard let selection = selectionRectInView else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: selection)
        outline.lineWidth = 2
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(for: event)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = screenPoint(for: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = screenPoint(for: event)
        guard let startPoint, let currentPoint,
              let selection = model.selection(start: startPoint, end: currentPoint, in: screenBounds) else {
            finish(nil)
            return
        }
        finish(selection)
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

    private var selectionRectInView: CGRect? {
        guard let startPoint, let currentPoint,
              let selection = model.selection(start: startPoint, end: currentPoint, in: screenBounds) else {
            return nil
        }
        return CGRect(x: selection.minX - screenBounds.minX,
                      y: selection.minY - screenBounds.minY,
                      width: selection.width,
                      height: selection.height)
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    private func finish(_ result: CGRect?) {
        guard !finished else { return }
        finished = true
        pendingResult = result
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
