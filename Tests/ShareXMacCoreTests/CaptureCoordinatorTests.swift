import CoreGraphics
import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Capture coordination")
struct CaptureCoordinatorTests {
    @Test("normalizes delay and only records successfully written screenshots")
    @MainActor func success() async throws {
        let store = CoordinatorHistory()
        var receivedDelay: Double?
        var writes = 0
        let date = Date(timeIntervalSince1970: 123)
        let coordinator = CaptureCoordinator(store: store, settings: { AppSettings(capture: CaptureSettings(delaySeconds: 90)) },
            hasPermission: { true }, delay: { receivedDelay = $0 },
            takeImage: { _, settings in
                #expect(settings.normalizedDelaySeconds == 60)
                return CapturedImage(image: Self.image(), windowTitle: "Editor", applicationName: "TextEdit")
            }, writeImage: { _, _ in writes += 1; return URL(fileURLWithPath: "/tmp/capture.png") }, now: { date })

        let result = await coordinator.capture(.window)
        let record = try result.get()
        #expect(receivedDelay == 60)
        #expect(writes == 1)
        #expect(record.timestamp == date)
        #expect(record.mode == .window)
        #expect(record.width == 2 && record.height == 2)
        #expect(record.windowTitle == "Editor")
        #expect(record.captureSettings?.delaySeconds == 60)
        #expect(await store.list(search: nil).count == 1)
        #expect(!coordinator.isCapturing)
    }

    @Test("copies successful screenshots when the capture setting is enabled")
    @MainActor func copiesEnabledScreenshot() async throws {
        let store = CoordinatorHistory()
        var copiedImage: CGImage?
        var copiedFile: URL?
        let coordinator = CaptureCoordinator(
            store: store,
            settings: { AppSettings(capture: CaptureSettings(copyToClipboard: true)) },
            hasPermission: { true },
            delay: { _ in },
            takeImage: { _, _ in CapturedImage(image: Self.image()) },
            writeImage: { _, _ in URL(fileURLWithPath: "/tmp/copied.png") },
            copyToClipboard: { image in copiedImage = image },
            copyFileToClipboard: { url in copiedFile = url }
        )

        _ = await coordinator.capture(.fullscreen)

        #expect(copiedImage != nil)
        #expect(copiedFile?.path == "/tmp/copied.png")
    }

    @Test("does not copy screenshots when the capture setting is disabled")
    @MainActor func skipsDisabledScreenshotCopy() async {
        let store = CoordinatorHistory()
        var copyCount = 0
        let coordinator = CaptureCoordinator(
            store: store,
            settings: { AppSettings(capture: CaptureSettings(copyToClipboard: false)) },
            hasPermission: { true },
            delay: { _ in },
            takeImage: { _, _ in CapturedImage(image: Self.image()) },
            writeImage: { _, _ in URL(fileURLWithPath: "/tmp/not-copied.png") },
            copyToClipboard: { _ in copyCount += 1 }
        )

        _ = await coordinator.capture(.fullscreen)

        #expect(copyCount == 0)
    }

    @Test("write failures never create a history record")
    @MainActor func writeFailure() async {
        let store = CoordinatorHistory()
        var confirmations = 0
        let coordinator = CaptureCoordinator(store: store, settings: { AppSettings() }, hasPermission: { true },
            delay: { _ in }, takeImage: { _, _ in CapturedImage(image: Self.image()) },
            writeImage: { _, _ in throw TestFailure.write }, onSaved: { _ in confirmations += 1 })
        if case .success = await coordinator.capture(.fullscreen) { Issue.record("Write failure reported success") }
        #expect(await store.list(search: nil).isEmpty)
        #expect(!coordinator.isCapturing)
        #expect(confirmations == 0)
    }

    @Test("cancelled selections neither write images nor record history")
    @MainActor func selectionCancellation() async {
        let store = CoordinatorHistory()
        var wrote = false
        var confirmations = 0
        let coordinator = CaptureCoordinator(store: store, settings: { AppSettings() }, hasPermission: { true },
            delay: { _ in }, takeImage: { _, _ in nil }, writeImage: { _, _ in wrote = true; return URL(fileURLWithPath: "/tmp/no.png") },
            onSaved: { _ in confirmations += 1 })
        if case .failure(.cancelled) = await coordinator.capture(.region) {} else { Issue.record("Expected cancellation") }
        #expect(!wrote)
        #expect(confirmations == 0)
        #expect(await store.list(search: nil).isEmpty)
    }

    @Test("permission denial stops before delay or capture")
    @MainActor func permissionGate() async {
        var invoked = false
        let coordinator = CaptureCoordinator(store: CoordinatorHistory(), settings: { AppSettings() }, hasPermission: { false },
            delay: { _ in invoked = true }, takeImage: { _, _ in invoked = true; return nil },
            writeImage: { _, _ in URL(fileURLWithPath: "/tmp/no.png") })
        if case .failure(.permissionRequired) = await coordinator.capture(.fullscreen) {} else { Issue.record("Expected permission error") }
        #expect(!invoked)
    }

    @Test("countdown cancellation stops before capture")
    @MainActor func delayCancellation() async {
        var invoked = false
        let coordinator = CaptureCoordinator(store: CoordinatorHistory(), settings: { AppSettings() }, hasPermission: { true },
            delay: { _ in throw CancellationError() }, takeImage: { _, _ in invoked = true; return nil },
            writeImage: { _, _ in URL(fileURLWithPath: "/tmp/no.png") })
        if case .failure(.cancelled) = await coordinator.capture(.fullscreen) {} else { Issue.record("Expected cancellation") }
        #expect(!invoked)
    }

    @Test("history failure preserves a useful path to the saved screenshot")
    @MainActor func historyFailure() async {
        var savedPath: String?
        let coordinator = CaptureCoordinator(store: CoordinatorHistory(failsInsert: true), settings: { AppSettings() }, hasPermission: { true },
            delay: { _ in }, takeImage: { _, _ in CapturedImage(image: Self.image()) },
            writeImage: { _, _ in URL(fileURLWithPath: "/tmp/saved.png") }, onSaved: { savedPath = $0.path })
        if case .failure(.historyFailed(let path, _)) = await coordinator.capture(.fullscreen) {
            #expect(path == "/tmp/saved.png")
        } else { Issue.record("Expected a saved-file history error") }
        #expect(savedPath == "/tmp/saved.png")
    }

    @Test("all screenshot modes share output size across file, clipboard, confirmation and history",
          arguments: [CaptureMode.fullscreen, .region, .window, .ocrRegion])
    @MainActor func outputSize(_ mode: CaptureMode) async throws {
        let source = Self.image()
        let store = CoordinatorHistory()
        var written: CGImage?
        var copied: CGImage?
        var confirmations: [CaptureRecord] = []
        let coordinator = CaptureCoordinator(store: store,
            settings: { AppSettings(capture: CaptureSettings(screenshotResolution: .half)) },
            hasPermission: { true }, delay: { _ in }, takeImage: { _, _ in CapturedImage(image: source) },
            writeImage: { image, _ in written = image; return URL(fileURLWithPath: "/tmp/output.png") },
            copyToClipboard: { copied = $0 }, onSaved: { record in
                #expect(written != nil)
                confirmations.append(record)
            })
        let record = try await coordinator.capture(mode).get()
        let expectedSize = mode == .ocrRegion ? 2 : 1
        #expect(written?.width == expectedSize)
        #expect(written?.height == expectedSize)
        #expect(copied === written)
        #expect(record.width == expectedSize && record.height == expectedSize)
        #expect(record.captureSettings?.screenshotResolution == (mode == .ocrRegion ? .full : .half))
        #expect(confirmations == [record])
        #expect(await store.list(search: nil).first?.record == record)
        if mode == .ocrRegion { #expect(written === source) }
    }

    private static func image() -> CGImage {
        CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

private enum TestFailure: Error { case write }
private actor CoordinatorHistory: ScreenshotStore {
    var records: [CaptureRecord] = []
    let failsInsert: Bool
    init(failsInsert: Bool = false) { self.failsInsert = failsInsert }
    func insert(_ record: CaptureRecord) throws {
        if failsInsert { throw TestFailure.write }
        records.append(record)
    }
    func list(search: String?) -> [ScreenshotHistoryEntry] { records.map { ScreenshotHistoryEntry(record: $0, isMissing: false) } }
    func delete(id: UUID, removeFile: Bool) { records.removeAll { $0.id == id } }
    func record(for id: UUID) -> ScreenshotHistoryEntry? { nil }
}
