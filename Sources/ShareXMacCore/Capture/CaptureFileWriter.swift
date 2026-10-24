import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CaptureFileWriter: Sendable {
    public enum WriterError: Error, LocalizedError, Sendable {
        case unableToEncodePNG
        case unableToCreateTemporaryFile

        public var errorDescription: String? {
            switch self {
            case .unableToEncodePNG: return "The image could not be encoded as PNG."
            case .unableToCreateTemporaryFile: return "A temporary capture file could not be created."
            }
        }
    }

    public init() {}

    @discardableResult
    public static func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        try CaptureFileWriter().writePNG(image, to: directory, date: date)
    }

    @discardableResult
    public func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = Self.dateFormatter.string(from: date)
        let temporary = directory.appendingPathComponent(".ShareX_\(UUID().uuidString).tmp")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw WriterError.unableToCreateTemporaryFile
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: temporary)
            throw WriterError.unableToEncodePNG
        }

        defer { try? fileManager.removeItem(at: temporary) }
        var suffix = 0
        while true {
            let filename = suffix == 0 ? "ShareX_\(stem).png" : "ShareX_\(stem)_\(suffix).png"
            let target = directory.appendingPathComponent(filename)
            do {
                // FileManager's move is an atomic rename on the same volume and
                // refuses to replace an existing destination.
                try fileManager.moveItem(at: temporary, to: target)
                return target
            } catch {
                // A concurrent writer may win the race after the destination
                // check; only treat that case as a collision.
                if fileManager.fileExists(atPath: target.path) {
                    suffix += 1
                } else {
                    throw error
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
