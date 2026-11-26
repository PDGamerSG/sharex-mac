import Foundation
import ShareXCore
import Testing
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

@Suite("Portable capture history and files")
struct PortableCaptureTests {
    @Test("concurrent connections can initialize the same new database or upgrade a Linux draft", arguments: [false, true])
    func concurrentHistory(migrate: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/history.sqlite")
        let legacyID = UUID()
        if migrate {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try createLinuxDraft(at: url, recordID: legacyID)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let store = try SQLiteScreenshotStore(databaseURL: url, createParentDirectory: true)
                    try await store.insert(CaptureRecord(mode: .fullscreen, path: "/\(index).png", width: 10, height: 20,
                                                         captureSettings: CaptureSettings(screenshotResolution: .half)))
                    await store.close()
                }
            }
            try await group.waitForAll()
        }
        let store = try SQLiteScreenshotStore(databaseURL: url)
        let entries = try await store.list()
        #expect(entries.filter { $0.record.captureSettings?.screenshotResolution == .half }.count == 12)
        #expect(entries.count == (migrate ? 13 : 12))
        if migrate {
            let legacy = try #require(try await store.record(for: legacyID)?.record)
            #expect(legacy.captureSettings == nil && legacy.displayCount == 2)
        }
    }

    @Test("independent publishers preserve each capture and leave no staging files")
    func concurrentPublishing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let contents = try await withThrowingTaskGroup(of: Data.self, returning: Set<Data>.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let url = try CaptureFilePublisher().writePNG(to: directory, date: date) {
                        try Data([UInt8(index)]).write(to: $0)
                    }
                    return try Data(contentsOf: url)
                }
            }
            var result = Set<Data>()
            for try await data in group { result.insert(data) }
            return result
        }
        #expect(contents.count == 12)
        let months = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let month = try #require(months.first)
        let files = try FileManager.default.contentsOfDirectory(at: month, includingPropertiesForKeys: nil)
        #expect(files.count == 12)
        #expect(files.allSatisfy { $0.pathExtension == "png" })
    }

    private func createLinuxDraft(at url: URL, recordID: UUID) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
            CREATE TABLE screenshots (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, mode TEXT NOT NULL,
                path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
                window_title TEXT, application_name TEXT, display_count INTEGER);
            INSERT INTO screenshots VALUES ('\(recordID.uuidString)', 0, 'region', '/old.png', 2, 3, NULL, NULL, 2);
            """
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }
}
