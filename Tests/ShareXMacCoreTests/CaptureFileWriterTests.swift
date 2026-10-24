import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShareXMacCore

@Suite("Capture file writing")
struct CaptureFileWriterTests {
    @Test("collisions receive numeric suffixes and preserve earlier captures")
    func collisionSuffixes() throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let first = try CaptureFileWriter().writePNG(image, to: directory.url, date: date)
        let second = try CaptureFileWriter().writePNG(image, to: directory.url, date: date)

        #expect(first.lastPathComponent.hasPrefix("ShareX_"))
        #expect(second.lastPathComponent != first.lastPathComponent)
        #expect(second.lastPathComponent.contains("_1.png"))
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        let firstData = try Data(contentsOf: first)
        let secondData = try Data(contentsOf: second)
        #expect(firstData == secondData)
    }

    @Test("writes a readable PNG without leaving temporary files")
    func atomicPNGOutput() throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let output = try CaptureFileWriter().writePNG(image, to: directory.url, date: Date(timeIntervalSince1970: 1_735_689_600))

        #expect(CGImageSourceCreateWithURL(output as CFURL, nil) != nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(files.first?.pathExtension == "png")
    }

    @Test("concurrent captures at one timestamp receive unique suffixes")
    func concurrentCollisionSuffixes() async throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let writer = CaptureFileWriter()
        let directoryURL = directory.url

        let outputs = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try writer.writePNG(image, to: directoryURL, date: date)
                }
            }

            var collected: [URL] = []
            for try await output in group {
                collected.append(output)
            }
            return collected
        }

        #expect(outputs.count == 8)
        #expect(Set(outputs.map(\.lastPathComponent)).count == 8)
        for output in outputs {
            #expect(CGImageSourceCreateWithURL(output as CFURL, nil) != nil)
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        #expect(files.count == 8)
        #expect(files.allSatisfy { !$0.lastPathComponent.hasPrefix(".ShareX_") })
    }

    @Test("injected encode and rename failures clean temporary files")
    func injectedFailuresCleanTemporaryFiles() throws {
        let directory = try TemporaryDirectory()
        let image = try onePixelImage()
        let date = Date(timeIntervalSince1970: 1_735_689_600)

        let encodeFailureWriter = CaptureFileWriter(
            makeDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            encodePNG: { _, url in
                try Data("partial".utf8).write(to: url)
                throw InjectedWriterFailure.encode
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            removeItem: { try? FileManager.default.removeItem(at: $0) }
        )
        do {
            _ = try encodeFailureWriter.writePNG(image, to: directory.url, date: date)
            Issue.record("The injected encode failure was not propagated")
        } catch {
            #expect(error is InjectedWriterFailure)
        }
        #expect(try temporaryFiles(in: directory.url).isEmpty)

        let renameFailureWriter = CaptureFileWriter(
            makeDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            encodePNG: { _, url in try Data("png".utf8).write(to: url) },
            moveItem: { _, _ in throw InjectedWriterFailure.rename },
            removeItem: { try? FileManager.default.removeItem(at: $0) }
        )
        do {
            _ = try renameFailureWriter.writePNG(image, to: directory.url, date: date)
            Issue.record("The injected rename failure was not propagated")
        } catch {
            #expect(error is InjectedWriterFailure)
        }
        #expect(try temporaryFiles(in: directory.url).isEmpty)
    }

    @Test("publishing refuses existing files and dangling symlinks without replacing them")
    func exclusivePublication() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("staged.tmp")
        let target = directory.url.appendingPathComponent("capture.png")
        let original = Data("earlier capture".utf8)
        try Data("new capture".utf8).write(to: source)
        try original.write(to: target)
        #expect(throws: Error.self) { try CaptureFileWriter.moveExclusively(source, target) }
        #expect(try Data(contentsOf: target) == original)
        #expect(FileManager.default.fileExists(atPath: source.path))

        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: "missing.png")
        #expect(throws: Error.self) { try CaptureFileWriter.moveExclusively(source, target) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == "missing.png")
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    private func onePixelImage() throws -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func temporaryFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".ShareX_") && $0.pathExtension == "tmp" }
    }
}

private enum InjectedWriterFailure: Error {
    case encode
    case rename
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
