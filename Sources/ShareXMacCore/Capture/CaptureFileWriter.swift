import CoreGraphics
import Foundation
import Darwin
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

    private let makeDirectory: @Sendable (URL) throws -> Void
    private let encodePNG: @Sendable (CGImage, URL) throws -> Void
    private let moveItem: @Sendable (URL, URL) throws -> Void
    private let removeItem: @Sendable (URL) -> Void

    public init() {
        self.init(
            makeDirectory: { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            },
            encodePNG: { image, url in
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw WriterError.unableToCreateTemporaryFile
                }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw WriterError.unableToEncodePNG
                }
            },
            moveItem: { source, destination in
                try Self.moveExclusively(source, destination)
            },
            removeItem: { url in
                try? FileManager.default.removeItem(at: url)
            }
        )
    }

    init(
        makeDirectory: @escaping @Sendable (URL) throws -> Void,
        encodePNG: @escaping @Sendable (CGImage, URL) throws -> Void,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        removeItem: @escaping @Sendable (URL) -> Void
    ) {
        self.makeDirectory = makeDirectory
        self.encodePNG = encodePNG
        self.moveItem = moveItem
        self.removeItem = removeItem
    }

    @discardableResult
    public static func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        try CaptureFileWriter().writePNG(image, to: directory, date: date)
    }

    @discardableResult
    public func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        try makeDirectory(directory)
        let stem = Self.dateFormatter.string(from: date)
        let temporary = directory.appendingPathComponent(".ShareX_\(UUID().uuidString).tmp")
        defer { removeItem(temporary) }
        try encodePNG(image, temporary)

        var suffix = 0
        while true {
            let filename = suffix == 0 ? "ShareX_\(stem).png" : "ShareX_\(stem)_\(suffix).png"
            let target = directory.appendingPathComponent(filename)
            do {
                // RENAME_EXCL atomically publishes the complete PNG without
                // replacing a winner from this or another process.
                try moveItem(temporary, target)
                return target
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                suffix += 1
            }
        }
    }

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    static func moveExclusively(_ source: URL, _ destination: URL) throws {
        let (status, errorNumber) = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                let status = renamex_np(sourcePath!, destinationPath!, UInt32(RENAME_EXCL))
                return (status, errno)
            }
        }
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorNumber))
        }
    }
}
