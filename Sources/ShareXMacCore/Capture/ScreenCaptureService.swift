import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

public final class ScreenCaptureService: @unchecked Sendable {
    public enum CaptureError: Error, LocalizedError, Sendable {
        case noDisplays
        case noWindows
        case noFrame

        public var errorDescription: String? {
            switch self {
            case .noDisplays: return "No displays are available for capture."
            case .noWindows: return "The selected window is no longer available."
            case .noFrame: return "Screen Capture Kit did not return an image frame."
            }
        }
    }

    public init() {}

    public func captureAllDisplays(showCursor: Bool = false) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        var captures: [DisplayCompositor.DisplayCapture] = []
        for display in content.displays {
            let image = try await capture(filter: SCContentFilter(display: display, excludingWindows: []),
                                          frame: display.frame, displayID: display.displayID,
                                          showCursor: showCursor)
            captures.append(image)
        }
        return DisplayCompositor().composite(captures)
    }

    public func captureWindow(_ window: SCWindow, showCursor: Bool = false) async throws -> CGImage {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { throw CaptureError.noWindows }
        let capture = try await capture(filter: SCContentFilter(desktopIndependentWindow: window), frame: frame,
                                        displayID: nil, showCursor: showCursor)
        return capture.image
    }

    private func capture(filter: SCContentFilter, frame: CGRect, displayID: CGDirectDisplayID?, showCursor: Bool) async throws -> DisplayCompositor.DisplayCapture {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = showCursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let scale: CGFloat
        if let displayID {
            let logicalWidth = max(CGFloat(CGDisplayBounds(displayID).width), 1)
            scale = max(CGFloat(CGDisplayPixelsWide(displayID)) / logicalWidth, 1)
            configuration.width = max(1, Int(frame.width * scale))
            configuration.height = max(1, Int(frame.height * scale))
        } else {
            scale = 1
            configuration.width = max(1, Int(frame.width))
            configuration.height = max(1, Int(frame.height))
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let output = try await SingleFrameOutput.capture(stream: stream)
        return DisplayCompositor.DisplayCapture(image: output, frame: frame, scale: scale)
    }
}

private final class SingleFrameOutput: NSObject, SCStreamOutput {
    private let context = CIContext()
    private var continuation: CheckedContinuation<CGImage, Error>?

    private override init() {
        super.init()
    }

    static func capture(stream: SCStream) async throws -> CGImage {
        let output = SingleFrameOutput()
        let streamBox = StreamBox(stream)
        let startBox = CaptureStartBox(stream: streamBox.stream, output: output)
        try streamBox.stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "ShareXMac.ScreenCapture"))
        let image: CGImage
        do {
            image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                output.continuation = continuation
                Task.detached {
                    do {
                        try await startBox.stream.startCapture()
                    } catch {
                        startBox.output.resume(with: .failure(error))
                    }
                }
            }
            try? await streamBox.stream.stopCapture()
        } catch {
            try? await streamBox.stream.stopCapture()
            throw error
        }
        return image
    }

    private func resume(with result: Result<CGImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), continuation != nil else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
            resume(with: .failure(ScreenCaptureService.CaptureError.noFrame))
            return
        }
        resume(with: .success(image))
    }
}

private final class StreamBox: @unchecked Sendable {
    let stream: SCStream
    init(_ stream: SCStream) { self.stream = stream }
}

private final class CaptureStartBox: @unchecked Sendable {
    let stream: SCStream
    let output: SingleFrameOutput
    init(stream: SCStream, output: SingleFrameOutput) {
        self.stream = stream
        self.output = output
    }
}
