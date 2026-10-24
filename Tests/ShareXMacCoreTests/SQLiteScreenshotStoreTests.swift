import Foundation
import Testing
@testable import ShareXMacCore

@Suite("SQLite screenshot history")
struct SQLiteScreenshotStoreTests {
    @Test("a new database creates an empty reusable schema")
    func schemaCreation() async throws {
        let directory = try HistoryTemporaryDirectory()
        let url = directory.url.appendingPathComponent("history.sqlite")
        let store = try SQLiteScreenshotStore(databaseURL: url)
        #expect(try await store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let reopened = try SQLiteScreenshotStore(databaseURL: url)
        #expect(try await reopened.list().isEmpty)
    }

    @Test("records persist all metadata and list newest first")
    func insertAndOrdering() async throws {
        let directory = try HistoryTemporaryDirectory()
        let url = directory.url.appendingPathComponent("history.sqlite")
        let store: any ScreenshotStore = try SQLiteScreenshotStore(databaseURL: url)
        let older = capture(path: directory.url.appendingPathComponent("older.png").path, time: 100)
        let newer = CaptureRecord(timestamp: Date(timeIntervalSince1970: 200.125), mode: .window, path: directory.url.appendingPathComponent("newer.png").path, width: 1920, height: 1080, windowTitle: "Sam's 文書", applicationName: "Editor")
        try await store.insert(newer)
        try await store.insert(older)
        let reopened = try SQLiteScreenshotStore(databaseURL: url)
        #expect(try await reopened.list().map(\.record) == [newer, older])
        #expect(try await reopened.record(for: newer.id)?.record == newer)
        #expect(try await reopened.record(for: UUID()) == nil)
    }

    @Test("filename search is case insensitive and excludes directory names")
    func filenameSearch() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let match = capture(path: directory.url.appendingPathComponent("Meeting NOTES.png").path)
        let directoryOnly = capture(path: directory.url.appendingPathComponent("notes/other.png").path)
        try await store.insert(match)
        try await store.insert(directoryOnly)
        #expect(try await store.list(search: "notes").map(\.record.id) == [match.id])
        #expect(try await store.list(search: "").count == 2)
        #expect(try await store.list(search: "absent").isEmpty)
    }

    @Test("search treats SQL syntax and wildcard characters as literal filename text")
    func literalSearch() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let special = capture(path: directory.url.appendingPathComponent("100%_O'Brien.png").path)
        try await store.insert(special)
        try await store.insert(capture(path: directory.url.appendingPathComponent("ordinary.png").path))
        #expect(try await store.list(search: "%_").map(\.record.id) == [special.id])
        #expect(try await store.list(search: "O'Brien").map(\.record.id) == [special.id])
        #expect(try await store.list(search: "' OR 1=1 --").isEmpty)
    }

    @Test("missing state follows file removal and recreation without changing metadata")
    func missingFiles() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let file = directory.url.appendingPathComponent("capture.png")
        let record = capture(path: file.path)
        try Data([1]).write(to: file)
        try await store.insert(record)
        #expect(try await store.list().first?.isMissing == false)
        try FileManager.default.removeItem(at: file)
        #expect(try await store.list().first?.isMissing == true)
        #expect(try await store.record(for: record.id)?.isMissing == true)
        try Data([2]).write(to: file)
        #expect(try await store.record(for: record.id)?.isMissing == false)
        #expect(try await store.record(for: record.id)?.record == record)
    }

    @Test("deleting only the history row preserves the image")
    func deleteRowOnly() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let file = directory.url.appendingPathComponent("capture.png")
        try Data([1]).write(to: file)
        let record = capture(path: file.path)
        try await store.insert(record)
        try await store.delete(id: record.id, removeFile: false)
        #expect(try await store.list().isEmpty)
        #expect(try await store.record(for: record.id) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("deleting an image removes its file and row and tolerates missing records")
    func deleteFileAndRow() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let file = directory.url.appendingPathComponent("capture.png")
        try Data([1]).write(to: file)
        let record = capture(path: file.path)
        try await store.insert(record)
        try await store.delete(id: record.id, removeFile: true)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
        #expect(try await store.list().isEmpty)
        try await store.delete(id: record.id, removeFile: true)
        let missing = capture(path: file.path)
        try await store.insert(missing)
        try await store.delete(id: missing.id, removeFile: true)
        #expect(try await store.list().isEmpty)
    }

    @Test("duplicate IDs throw without replacing the stored record")
    func duplicateID() async throws {
        let directory = try HistoryTemporaryDirectory()
        let store = try SQLiteScreenshotStore(databaseURL: directory.url.appendingPathComponent("history.sqlite"))
        let original = capture(path: "/tmp/original.png")
        try await store.insert(original)
        await #expect(throws: Error.self) { try await store.insert(original) }
        #expect(try await store.list().map(\.record) == [original])
    }

    private func capture(path: String, time: TimeInterval = 100) -> CaptureRecord {
        CaptureRecord(timestamp: Date(timeIntervalSince1970: time), mode: .region, path: path, width: 640, height: 480)
    }
}

private final class HistoryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
