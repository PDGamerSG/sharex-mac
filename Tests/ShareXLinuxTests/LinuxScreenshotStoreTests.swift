import Foundation
import ShareXLinuxCore
import Testing

struct LinuxScreenshotStoreTests {
    @Test("Linux history stores records newest first and marks missing files")
    func history() async throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let database = directory.url.appendingPathComponent("history.sqlite")
        let image = directory.url.appendingPathComponent("capture.png")
        try Data("png".utf8).write(to: image)
        let store = try LinuxScreenshotStore(databaseURL: database)
        let older = LinuxCaptureRecord(timestamp: Date(timeIntervalSince1970: 1), mode: .fullscreen,
                                       path: image.path, width: 1, height: 1)
        let newer = LinuxCaptureRecord(timestamp: Date(timeIntervalSince1970: 2), mode: .region,
                                       path: directory.url.appendingPathComponent("missing.png").path, width: 2, height: 2)
        try await store.insert(older)
        try await store.insert(newer)
        let records = try await store.list()
        #expect(records.map { $0.record.id } == [newer.id, older.id])
        #expect(records.first?.isMissing == true)
        #expect(try await store.list(search: "capture").count == 1)
        try await store.delete(id: older.id, removeFile: true)
        #expect(!FileManager.default.fileExists(atPath: image.path))
    }
}
