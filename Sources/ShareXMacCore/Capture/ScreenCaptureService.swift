import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public final class ScreenCaptureService: Sendable {
    public enum CaptureError: Error, LocalizedError, Sendable {
        case noDisplays
        case noWindows
        case noFrame
        case streamStopped(String)

        public var errorDescription: String? {
            switch self {
            case .noDisplays: return "No displays are available for capture."
            case .noWindows: return "The selected window is no longer available."
            case .noFrame: return "Screen Capture Kit did not return an image frame."
            case .streamStopped(let reason): return "The screen capture stream stopped: \(reason)"
            }
        }
    }

    public init() {}

    public func captureAllDisplays(showCursor: Bool = false) async throws -> CGImage {
        try await captureDesktop(showCursor: showCursor).image
    }

    public func captureDesktop(showCursor: Bool = false) async throws -> CapturedDesktop {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        var captures: [DisplayCompositor.DisplayCapture] = []
        for display in content.displays {
            let image = try await capture(filter: SCContentFilter(display: display, excludingWindows: ownWindows),
                                          frame: display.frame, displayID: display.displayID,
                                          showCursor: showCursor)
            captures.append(image)
        }
        let bounds = captures.reduce(CGRect.null) { $0.union($1.frame) }
        return CapturedDesktop(image: DisplayCompositor().composite(captures),
                               geometry: DesktopGeometry(quartzBounds: bounds, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height), displayCount: captures.count)
    }

    public func captureWindow(_ window: SCWindow, showCursor: Bool = false) async throws -> CGImage {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { throw CaptureError.noWindows }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale: CGFloat
        if #available(macOS 14.0, *) {
            scale = CGFloat(filter.pointPixelScale)
        } else {
            scale = backingScale(for: frame)
        }
        let capture = try await capture(filter: filter, frame: frame,
                                        displayID: nil, scale: scale, showCursor: showCursor)
        return capture.image
    }

    private func capture(filter: SCContentFilter, frame: CGRect, displayID: CGDirectDisplayID?, showCursor: Bool) async throws -> DisplayCompositor.DisplayCapture {
        let scale = displayID.map { displayScale(for: $0) } ?? 1
        return try await capture(filter: filter, frame: frame, displayID: displayID, scale: scale, showCursor: showCursor)
    }

    private func capture(filter: SCContentFilter, frame: CGRect, displayID: CGDirectDisplayID?, scale: CGFloat, showCursor: Bool) async throws -> DisplayCompositor.DisplayCapture {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = showCursor
        // Use full RGB samples, without video chroma subsampling.
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 14.0, *) { configuration.captureResolution = .best }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.width = max(1, Int(ceil(frame.width * max(scale, 1))))
        configuration.height = max(1, Int(ceil(frame.height * max(scale, 1))))

        let queue = DispatchQueue(label: "ShareXMac.ScreenCapture")
        let driver = ScreenCaptureStreamDriver(filter: filter, configuration: configuration, queue: queue)
        let lifecycle = CaptureStreamLifecycle<CGImage>(driver: driver, queue: queue)
        queue.sync {
            driver.receive = { [weak lifecycle] result in lifecycle?.receive(result) }
        }
        let image = try await lifecycle.capture()
        return DisplayCompositor.DisplayCapture(image: image, frame: frame, scale: scale)
    }

    private func displayScale(for displayID: CGDirectDisplayID) -> CGFloat {
        // CGDisplayPixelsWide is measured in logical pixels on Retina modes.
        // The current mode exposes the actual backing pixel dimensions.
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return max(CGFloat(mode.pixelWidth) / CGFloat(mode.width), 1)
    }

    private func backingScale(for frame: CGRect) -> CGFloat {
        var displayCount: UInt32 = 0
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &displayCount) == .success else {
            return 1
        }

        var scale: CGFloat = 1
        for displayID in displayIDs.prefix(Int(displayCount)) {
            let displayFrame = CGDisplayBounds(displayID)
            guard displayFrame.intersects(frame) else { continue }
            scale = max(scale, displayScale(for: displayID))
        }
        return scale
    }
}

/// ScreenCaptureKit is confined to the lifecycle's serial queue. The delegate
/// callback is the only callback with an unspecified queue, so it forwards only
/// the error before accessing any owned state.
private final class ScreenCaptureStreamDriver: NSObject, CaptureStreamDriver, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let queue: DispatchQueue
    private let context = CIContext()
    private var stream: SCStream?
    var receive: (@Sendable (Result<CGImage, Error>) -> Void)?

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, queue: DispatchQueue) {
        self.filter = filter
        self.configuration = configuration
        self.queue = queue
    }

    func install() throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
    }

    func start(completion: @escaping @Sendable (Error?) -> Void) {
        stream!.startCapture(completionHandler: completion)
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        stream!.stopCapture { _ in completion() }
    }

    func remove() {
        try? stream?.removeStreamOutput(self, type: .screen)
        stream = nil
        receive = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            receive?(.failure(ScreenCaptureService.CaptureError.noFrame))
            return
        }
        switch ScreenCaptureFrameDisposition(status: status) {
        case .wait: return
        case .fail:
            receive?(.failure(ScreenCaptureService.CaptureError.noFrame))
            return
        case .capture: break
        }
        guard CMSampleBufferDataIsReady(sampleBuffer), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            receive?(.failure(ScreenCaptureService.CaptureError.noFrame))
            return
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else {
            receive?(.failure(ScreenCaptureService.CaptureError.noFrame))
            return
        }
        receive?(.success(cgImage))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            self.receive?(.failure(ScreenCaptureService.CaptureError.streamStopped(error.localizedDescription)))
        }
    }
}

enum ScreenCaptureFrameDisposition {
    case capture, wait, fail

    init(status: SCFrameStatus) {
        switch status {
        case .complete: self = .capture
        case .started, .idle, .blank, .suspended: self = .wait
        case .stopped: self = .fail
        @unknown default: self = .fail
        }
    }
}
