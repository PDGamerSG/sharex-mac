import AppKit
import ShareXMacCore
import Testing
@testable import ShareXMac

@Suite("Capture confirmation")
@MainActor struct CaptureConfirmationTests {
    @Test("OCR skips the saved notification and regular screenshots still show it",
          arguments: [(CaptureMode.fullscreen, 1), (.region, 1), (.window, 1), (.ocrRegion, 0)])
    func notificationVisibility(mode: CaptureMode, expectedCount: Int) {
        let application = NSApplication.shared
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let confirmation = CaptureConfirmation()
        defer { confirmation.close() }
        let record = CaptureRecord(mode: mode, path: "/tmp/capture.png", width: 1, height: 1)

        confirmation.show(record: record)

        let newVisibleWindows = application.windows.filter {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.isVisible
        }
        #expect(newVisibleWindows.count == expectedCount)
    }
}
