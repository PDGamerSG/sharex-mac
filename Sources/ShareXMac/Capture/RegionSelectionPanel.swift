import AppKit
import ShareXMacCore

@MainActor
public final class RegionSelectionPanel {
    public init() {}

    /// Bounds and result use AppKit coordinates.
    public func select(image: CGImage, screenBounds: CGRect) async -> CGRect? {
        guard !Task.isCancelled, !NSScreen.screens.isEmpty, !screenBounds.isEmpty else { return nil }
        let session = RegionSelectionSession(image: image, bounds: screenBounds)
        let panels = NSScreen.screens.map { screen in
            let panel = SelectionPanelWindow(contentRect: screen.frame)
            let view = RegionSelectionView(session: session, screenFrame: screen.frame)
            session.redraw.append { [weak view] in view?.needsDisplay = true }
            panel.contentView = view
            panel.makeFirstResponder(view)
            panel.orderFrontRegardless()
            return panel
        }
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in session.result.finish(nil) }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            panels.forEach { $0.orderOut(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
        (panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels.first)?.makeKey()
        return await session.result.wait()
    }
}

@MainActor
private final class RegionSelectionSession {
    let image: NSImage
    let bounds: CGRect
    let result = SelectionResult<CGRect>()
    var redraw: [() -> Void] = []
    var start: CGPoint?
    var end: CGPoint?

    init(image: CGImage, bounds: CGRect) {
        self.image = NSImage(cgImage: image, size: bounds.size)
        self.bounds = bounds
    }
    var selection: CGRect? {
        guard let start, let end else { return nil }
        return RegionSelectionModel().selection(start: start, end: end, in: bounds)
    }
    func update(_ point: CGPoint, beginning: Bool = false) {
        if beginning { start = point }
        end = point
        redraw.forEach { $0() }
    }
}

private final class RegionSelectionView: NSView {
    private let session: RegionSelectionSession
    private let screenFrame: CGRect

    init(session: RegionSelectionSession, screenFrame: CGRect) {
        self.session = session
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let imageRect = session.bounds.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        session.image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()
        guard let selection = session.selection else { return }
        let local = selection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: local).addClip()
        session.image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: local)
        outline.lineWidth = 2
        outline.stroke()
    }
    override func mouseDown(with event: NSEvent) { session.update(point(for: event), beginning: true) }
    override func mouseDragged(with event: NSEvent) { session.update(point(for: event)) }
    override func mouseUp(with event: NSEvent) {
        session.update(point(for: event))
        session.result.finish(session.selection)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { session.result.finish(nil) }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { session.result.finish(nil) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func point(for event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation }
}
