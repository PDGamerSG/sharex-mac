import Foundation
import SQLite3
import Testing
@testable import ShareXMacCore

@Suite("Capture history metadata")
struct CaptureMetadataTests {
    @Test("migrates an existing database and preserves old rows and new capture options")
    func migration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let oldID = UUID()
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        let schema = "CREATE TABLE screenshots (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, mode TEXT NOT NULL, path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, window_title TEXT, application_name TEXT)"
        #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, "INSERT INTO screenshots VALUES ('\(oldID.uuidString)', 0, 'region', '/tmp/old.png', 10, 20, NULL, NULL)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)

        let store = try SQLiteScreenshotStore(databaseURL: url)
        let old = try await store.record(for: oldID)
        #expect(old?.record.path == "/tmp/old.png")
        #expect(old?.record.captureSettings == nil)
        let record = CaptureRecord(mode: .fullscreen, path: "/tmp/new.png", width: 100, height: 50,
                                   captureSettings: CaptureSettings(showCursor: true, delaySeconds: 3), displayCount: 2)
        try await store.insert(record)
        let stored = try #require(await store.record(for: record.id)?.record)
        #expect(stored.id == record.id)
        #expect(stored.mode == record.mode)
        #expect(stored.path == record.path)
        #expect(stored.width == record.width && stored.height == record.height)
        #expect(stored.captureSettings == record.captureSettings)
        #expect(stored.displayCount == record.displayCount)
        await store.close()
        let reopened = try SQLiteScreenshotStore(databaseURL: url)
        #expect(try await reopened.list().count == 2)
        #expect(try await reopened.record(for: record.id)?.record.displayCount == 2)
        await reopened.close()
    }

    @Test("older Codable records decode without capture option fields")
    func oldJSON() throws {
        let record = CaptureRecord(mode: .region, path: "/tmp/old.png", width: 1, height: 2)
        let encoded = try JSONEncoder().encode(record)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "captureSettings")
        object.removeValue(forKey: "displayCount")
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.captureSettings == nil)
        #expect(decoded.id == record.id)
    }
}
