import Foundation

public struct LinuxSavedCapture: Sendable {
    public let record: LinuxCaptureRecord
    public let warning: String?
}

/// The desktop owns the countdown and picker UI. This operation owns the staged image,
/// publication, history row and optional clipboard copy for one completed selection.
public struct LinuxAppController: Sendable {
    public typealias Capture = @Sendable (LinuxCaptureMode, LinuxCaptureSettings, URL) async throws -> LinuxCapturedImage
    public typealias Resize = @Sendable (URL, Int, Int, URL) async throws -> URL

    private let takeImage: Capture
    private let resize: Resize
    private let insert: @Sendable (LinuxCaptureRecord) async throws -> Void
    private let copyImage: @Sendable (URL) async throws -> Void

    public init(capture: @escaping Capture, resize: @escaping Resize,
                insert: @escaping @Sendable (LinuxCaptureRecord) async throws -> Void,
                copyImage: @escaping @Sendable (URL) async throws -> Void) {
        self.takeImage = capture
        self.resize = resize
        self.insert = insert
        self.copyImage = copyImage
    }

    public func capture(_ mode: LinuxCaptureMode, settings: LinuxCaptureSettings) async throws -> LinuxSavedCapture {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXLinux-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        var options = settings
        if mode == .ocrRegion { options.screenshotResolution = .full }
        let captured = try await takeImage(mode, options, staging)
        let scale = options.screenshotResolution.scale
        let width = max(1, Int((Double(captured.width) * scale).rounded()))
        let height = max(1, Int((Double(captured.height) * scale).rounded()))
        let png = scale == 1 ? captured.path : try await resize(captured.path, width, height, staging)
        try Task.checkCancellation()
        let date = Date()
        let url = try LinuxCaptureFileWriter().writePNG(from: png, to: URL(fileURLWithPath: options.screenshotFolderPath), date: date)
        let record = LinuxCaptureRecord(timestamp: date, mode: mode, path: url.path, width: width, height: height,
                                        windowTitle: captured.windowTitle, applicationName: captured.applicationName,
                                        captureSettings: options.options, displayCount: captured.displayCount)
        var warnings: [String] = []
        do { try await insert(record) }
        catch { warnings.append("Saved \(url.path). History could not be updated. \(error.localizedDescription)") }
        if options.copyToClipboard && mode != .ocrRegion {
            do { try await copyImage(url) }
            catch { warnings.append("The PNG was saved, but copying it failed. \(error.localizedDescription)") }
        }
        return LinuxSavedCapture(record: record, warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
    }
}
