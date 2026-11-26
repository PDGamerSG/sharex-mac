import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Stage a complete image on the destination filesystem before publishing its name.
package struct CaptureFilePublisher: Sendable {
    private let makeDirectory: @Sendable (URL) throws -> Void
    private let publish: @Sendable (URL, URL) throws -> Void
    private let removeTemporary: @Sendable (URL) -> Void

    package init(
        makeDirectory: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        publish: @escaping @Sendable (URL, URL) throws -> Void = Self.publishExclusively,
        removeTemporary: @escaping @Sendable (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }
    ) {
        self.makeDirectory = makeDirectory
        self.publish = publish
        self.removeTemporary = removeTemporary
    }

    package func writePNG(to directory: URL, date: Date, prepare: (URL) throws -> Void) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = formatter.string(from: date)
        formatter.dateFormat = "yyyy-MM"
        let month = directory.appendingPathComponent(formatter.string(from: date), isDirectory: true)
        try makeDirectory(month)

        let temporary = month.appendingPathComponent(".ShareX_\(UUID().uuidString).tmp")
        defer { removeTemporary(temporary) }
        try prepare(temporary)
        var suffix = 0
        while true {
            let filename = suffix == 0 ? "ShareX_\(stem).png" : "ShareX_\(stem)_\(suffix).png"
            let target = month.appendingPathComponent(filename)
            do {
                try publish(temporary, target)
                return target
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                suffix += 1
            }
        }
    }

    package static func publishExclusively(_ source: URL, _ target: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            target.withUnsafeFileSystemRepresentation { targetPath in
                guard let sourcePath, let targetPath else { return Int32(EINVAL) }
                #if os(Linux)
                // link atomically fails even for an existing dangling symlink.
                // The deferred cleanup releases the staging name after publication.
                let status = link(sourcePath, targetPath)
                #else
                let status = renamex_np(sourcePath, targetPath, UInt32(RENAME_EXCL))
                #endif
                return status == 0 ? 0 : errno
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
    }
}
