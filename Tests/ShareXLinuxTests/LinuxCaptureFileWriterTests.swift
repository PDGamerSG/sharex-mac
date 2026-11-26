import Foundation
import ShareXLinuxCore
import Testing

struct LinuxCaptureFileWriterTests {
    @Test("Linux writer creates monthly folders and collision suffixes")
    func writesCollisionSafeFiles() throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let source = directory.url.appendingPathComponent("source.png")
        try Data("png".utf8).write(to: source)
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let first = try LinuxCaptureFileWriter().writePNG(from: source, to: directory.url, date: date)
        try Data("png2".utf8).write(to: source)
        let second = try LinuxCaptureFileWriter().writePNG(from: source, to: directory.url, date: date)
        #expect(first.deletingLastPathComponent().lastPathComponent.count == 7)
        #expect(first.lastPathComponent.hasPrefix("ShareX_"))
        #expect(second.lastPathComponent.hasSuffix("_1.png"))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }
}
