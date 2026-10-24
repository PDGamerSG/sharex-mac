import CoreGraphics
import Foundation

public struct CapturedImage: Sendable {
    public let image: CGImage
    public let windowTitle: String?
    public let applicationName: String?
    public let displayCount: Int?
    public init(image: CGImage, windowTitle: String? = nil, applicationName: String? = nil, displayCount: Int? = nil) {
        self.image = image
        self.windowTitle = windowTitle
        self.applicationName = applicationName
        self.displayCount = displayCount
    }
}

@MainActor
public final class CaptureCoordinator {
    public enum CaptureError: Error, LocalizedError {
        case busy
        case cancelled
        case permissionRequired
        case failed(String)
        case historyFailed(path: String, reason: String)
        public var errorDescription: String? {
            switch self {
            case .busy: return "A capture is already in progress."
            case .cancelled: return "Capture cancelled."
            case .permissionRequired: return "Allow ShareX Mac in System Settings → Privacy & Security → Screen Recording, then relaunch the app."
            case .failed(let reason): return reason
            case .historyFailed(let path, let reason): return "The screenshot was saved to \(path), but history could not be updated: \(reason)"
            }
        }
    }

    public private(set) var isCapturing = false
    private let store: any ScreenshotStore
    private let settings: () -> AppSettings
    private let hasPermission: () -> Bool
    private let delay: @MainActor (Double) async throws -> Void
    private let takeImage: @MainActor (CaptureMode, CaptureSettings) async throws -> CapturedImage?
    private let writeImage: @MainActor (CGImage, Date) async throws -> URL
    private let copyToClipboard: @MainActor (CGImage) -> Void
    private let copyFileToClipboard: @MainActor (URL) -> Void
    private let onSaved: @MainActor (CaptureRecord) -> Void
    private let now: () -> Date

    public init(store: any ScreenshotStore, settings: @escaping () -> AppSettings,
                hasPermission: @escaping () -> Bool, delay: @escaping @MainActor (Double) async throws -> Void,
                takeImage: @escaping @MainActor (CaptureMode, CaptureSettings) async throws -> CapturedImage?,
                writeImage: @escaping @MainActor (CGImage, Date) async throws -> URL,
                now: @escaping () -> Date = Date.init,
                copyToClipboard: @escaping @MainActor (CGImage) -> Void = { _ in },
                copyFileToClipboard: @escaping @MainActor (URL) -> Void = { _ in },
                onSaved: @escaping @MainActor (CaptureRecord) -> Void = { _ in }) {
        self.store = store
        self.settings = settings
        self.hasPermission = hasPermission
        self.delay = delay
        self.takeImage = takeImage
        self.writeImage = writeImage
        self.copyToClipboard = copyToClipboard
        self.copyFileToClipboard = copyFileToClipboard
        self.onSaved = onSaved
        self.now = now
    }

    public func capture(_ mode: CaptureMode) async -> Result<CaptureRecord, CaptureError> {
        guard !isCapturing else { return .failure(.busy) }
        isCapturing = true
        defer { isCapturing = false }
        guard hasPermission() else { return .failure(.permissionRequired) }
        do {
            try Task.checkCancellation()
            var options = settings().capture
            options.delaySeconds = options.normalizedDelaySeconds
            // OCR needs the original text detail, regardless of the output
            // preference used for ordinary screenshots.
            if mode == .ocrRegion { options.screenshotResolution = .full }
            try await delay(options.normalizedDelaySeconds)
            try Task.checkCancellation()
            guard let capture = try await takeImage(mode, options) else { return .failure(.cancelled) }
            try Task.checkCancellation()
            let resolution = options.screenshotResolution
            let image = try await Task.detached(priority: .userInitiated) {
                try resolution.prepare(capture.image)
            }.value
            try Task.checkCancellation()
            let date = now()
            let url = try await writeImage(image, date)
            if options.copyToClipboard {
                // Copy the canonical PNG once. Avoiding a second ImageIO encode
                // keeps capture CPU, memory, and energy use low while preserving
                // the exact bytes written to disk.
                copyFileToClipboard(url)
            }
            // Once written, finish recording metadata even if cancellation is
            // requested. Never create a row before a successful atomic write.
            let record = CaptureRecord(timestamp: date, mode: mode, path: url.path,
                                       width: image.width, height: image.height,
                                       windowTitle: capture.windowTitle, applicationName: capture.applicationName,
                                       captureSettings: options, displayCount: capture.displayCount)
            // A saved file deserves confirmation even if history later fails.
            onSaved(record)
            do { try await store.insert(record) }
            catch { return .failure(.historyFailed(path: url.path, reason: error.localizedDescription)) }
            return .success(record)
        } catch is CancellationError { return .failure(.cancelled) }
        catch { return .failure(.failed(error.localizedDescription)) }
    }
}
