import Foundation
import SQLite3

public actor SQLiteScreenshotStore: ScreenshotStore {
    private var db: OpaquePointer?
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(handle)
            throw StoreError.database(message)
        }
        db = handle
        do { try Self.createSchema(handle: handle!) }
        catch { sqlite3_close(handle); db = nil; throw error }
    }


    public func insert(_ record: CaptureRecord) throws {
        let sql = "INSERT INTO screenshots (id, timestamp, mode, path, width, height, window_title, application_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(record, to: statement)
        try step(statement)
    }

    public func list(search: String? = nil) throws -> [ScreenshotHistoryEntry] {
        var sql = "SELECT id, timestamp, mode, path, width, height, window_title, application_name FROM screenshots"
        if let search, !search.isEmpty { sql += " WHERE lower(path) LIKE '%' || lower(?) || '%'" }
        sql += " ORDER BY timestamp DESC, rowid DESC"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let search, !search.isEmpty { try bindText(search, index: 1, statement: statement) }
        var result: [ScreenshotHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let entry = try decode(statement)
            if let search, !search.isEmpty {
                let filename = URL(fileURLWithPath: entry.record.path).lastPathComponent.lowercased()
                if !filename.contains(search.lowercased()) { continue }
            }
            result.append(entry)
        }
        return result
    }

    public func delete(id: UUID, removeFile: Bool) throws {
        if removeFile, let entry = try record(for: id) { try? FileManager.default.removeItem(atPath: entry.record.path) }
        let statement = try prepare("DELETE FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, index: 1, statement: statement)
        try step(statement)
    }

    public func record(for id: UUID) throws -> ScreenshotHistoryEntry? {
        let statement = try prepare("SELECT id, timestamp, mode, path, width, height, window_title, application_name FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, index: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decode(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer { var statement: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw currentError() }; return statement }

    private func bind(_ record: CaptureRecord, to statement: OpaquePointer) throws {
        try bindText(record.id.uuidString, index: 1, statement: statement)
        try bindDouble(record.timestamp.timeIntervalSince1970, index: 2, statement: statement)
        try bindText(record.mode.rawValue, index: 3, statement: statement)
        try bindText(record.path, index: 4, statement: statement)
        try bindInt32(Int32(record.width), index: 5, statement: statement)
        try bindInt32(Int32(record.height), index: 6, statement: statement)
        try bindOptionalText(record.windowTitle, index: 7, statement: statement)
        try bindOptionalText(record.applicationName, index: 8, statement: statement)
    }

    private func decode(_ statement: OpaquePointer) throws -> ScreenshotHistoryEntry {
        guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))), let mode = CaptureMode(rawValue: String(cString: sqlite3_column_text(statement, 2))) else { throw StoreError.database("invalid stored record") }
        let path = String(cString: sqlite3_column_text(statement, 3))
        let record = CaptureRecord(id: id, timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), mode: mode, path: path, width: Int(sqlite3_column_int(statement, 4)), height: Int(sqlite3_column_int(statement, 5)), windowTitle: optionalText(statement, 6), applicationName: optionalText(statement, 7))
        return ScreenshotHistoryEntry(record: record, isMissing: !FileManager.default.fileExists(atPath: path))
    }

    private static func createSchema(handle: OpaquePointer) throws {
        let sql = "CREATE TABLE IF NOT EXISTS screenshots (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, mode TEXT NOT NULL, path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, window_title TEXT, application_name TEXT)"
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.database(String(cString: sqlite3_errmsg(handle))) }
    }

    private func currentError() -> StoreError { StoreError.database(String(cString: sqlite3_errmsg(db))) }
    private func step(_ statement: OpaquePointer) throws { guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() } }
    private func bindText(_ value: String, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw currentError() } }
    private func bindOptionalText(_ value: String?, index: Int32, statement: OpaquePointer) throws { guard (value == nil ? sqlite3_bind_null(statement, index) : sqlite3_bind_text(statement, index, value!, -1, SQLITE_TRANSIENT)) == SQLITE_OK else { throw currentError() } }
    private func bindDouble(_ value: Double, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw currentError() } }
    private func bindInt32(_ value: Int32, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_int(statement, index, value) == SQLITE_OK else { throw currentError() } }
    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? { guard let value = sqlite3_column_text(statement, index) else { return nil }; return String(cString: value) }
}

public enum StoreError: Error, LocalizedError, Sendable { case database(String); public var errorDescription: String? { if case .database(let message) = self { return message }; return nil } }

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
