import CoreGraphics
import Foundation
import ImageIO
import ShareXCore
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

    private let publisher: CaptureFilePublisher
    private let encodePNG: @Sendable (CGImage, URL) throws -> Void

    public init() {
        publisher = CaptureFilePublisher()
        encodePNG = { image, url in
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw WriterError.unableToCreateTemporaryFile
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw WriterError.unableToEncodePNG }
        }
    }

    init(
        makeDirectory: @escaping @Sendable (URL) throws -> Void,
        encodePNG: @escaping @Sendable (CGImage, URL) throws -> Void,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        removeItem: @escaping @Sendable (URL) -> Void
    ) {
        publisher = CaptureFilePublisher(makeDirectory: makeDirectory, publish: moveItem, removeTemporary: removeItem)
        self.encodePNG = encodePNG
    }

    @discardableResult
    public static func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        try CaptureFileWriter().writePNG(image, to: directory, date: date)
    }

    @discardableResult
    public func writePNG(_ image: CGImage, to directory: URL, date: Date = Date()) throws -> URL {
        try publisher.writePNG(to: directory, date: date) { try encodePNG(image, $0) }
    }

    static func moveExclusively(_ source: URL, _ destination: URL) throws {
        try CaptureFilePublisher.publishExclusively(source, destination)
    }
}
