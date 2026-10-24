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
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let orderedIDs = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let order = Dictionary(orderedIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let windows = content.windows.filter {
            $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0 &&
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && order[$0.windowID] != nil
        }.sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
        guard !windows.isEmpty else { throw ScreenCaptureService.CaptureError.noWindows }
        let session = WindowPickerSession(windows: windows)
        let panels = NSScreen.screens.map { screen in
            let panel = SelectionPanelWindow(contentRect: screen.frame)
            let view = WindowPickerView(session: session, screenFrame: screen.frame)
            session.redraw.append { [weak view] in view?.needsDisplay = true }
            panel.contentView = view
            panel.makeFirstResponder(view)
            panel.orderFrontRegardless()
            return panel
        }
        guard !panels.isEmpty else { throw ScreenCaptureService.CaptureError.noDisplays }
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in session.result.finish(nil) }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            panels.forEach { $0.orderOut(nil) }
        }
        session.update(NSEvent.mouseLocation)
        NSApp.activate(ignoringOtherApps: true)
        (panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels.first)?.makeKey()
        let selected = await session.result.wait()
        return windows.first { $0.windowID == selected }
    }
}

@MainActor
private final class WindowPickerSession {
    let windows: [SCWindow]
    let geometry = DesktopGeometry(quartzBounds: .zero, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
    let result = SelectionResult<CGWindowID>()
    var redraw: [() -> Void] = []
    var hovered: SCWindow?

    init(windows: [SCWindow]) { self.windows = windows }
    func frame(for window: SCWindow) -> CGRect { geometry.appKitRect(fromQuartz: window.frame) }
    func update(_ point: CGPoint) {
        hovered = windows.first { frame(for: $0).contains(point) }
        redraw.forEach { $0() }
    }
}

private final class WindowPickerView: NSView {
    private let session: WindowPickerSession
    private let screenFrame: CGRect

    init(session: WindowPickerSession, screenFrame: CGRect) {
        self.session = session
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()
        guard let hovered = session.hovered else { return }
        let rect = session.frame(for: hovered).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        rect.fill()
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 3
        outline.stroke()
    }
    override func mouseMoved(with event: NSEvent) { session.update(point(for: event)) }
    override func mouseDown(with event: NSEvent) {
        session.update(point(for: event))
        if let hovered = session.hovered { session.result.finish(hovered.windowID) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { session.result.finish(nil) }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { session.result.finish(nil) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func point(for event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation }
}
