import Foundation
import ShareXCore

public struct LinuxCaptureFileWriter: Sendable {
    private let publisher = CaptureFilePublisher()

    public init() {}

    @discardableResult
    public func writePNG(from source: URL, to directory: URL, date: Date = Date()) throws -> URL {
        let output = try publisher.writePNG(to: directory, date: date) { temporary in
            try FileManager.default.copyItem(at: source, to: temporary)
        }
        try? FileManager.default.removeItem(at: source)
        return output
    }
}
