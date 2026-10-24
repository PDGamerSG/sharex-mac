import Foundation
import SQLite3

public actor SQLiteScreenshotStore: ScreenshotStore {
    private let connection: SQLiteConnectionHolder
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(handle)
            throw StoreError.database(message)
        }
        let connection = SQLiteConnectionHolder(handle: handle!)
        self.connection = connection
        do { try Self.createSchema(handle: handle!) }
        catch { connection.close(); throw error }
    }


    public func close() {
        connection.close()
    }

    public func insert(_ record: CaptureRecord) throws {
        let sql = "INSERT INTO screenshots (id, timestamp, mode, path, width, height, window_title, application_name, capture_settings, display_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(record, to: statement)
        try step(statement)
    }

    public func list(search: String? = nil) throws -> [ScreenshotHistoryEntry] {
        var sql = "SELECT id, timestamp, mode, path, width, height, window_title, application_name, capture_settings, display_count FROM screenshots"
        sql += " ORDER BY timestamp DESC, rowid DESC"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var result: [ScreenshotHistoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                let entry = try decode(statement)
                if let search, !search.isEmpty {
                    let filename = URL(fileURLWithPath: entry.record.path).lastPathComponent
                    if !filename.localizedCaseInsensitiveContains(search) { continue }
                }
                result.append(entry)
            } else if status == SQLITE_DONE {
                return result
            } else {
                throw currentError()
            }
        }
    }

    public func delete(id: UUID, removeFile: Bool) throws {
        if removeFile, let entry = try record(for: id) {
            do { try FileManager.default.removeItem(atPath: entry.record.path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {}
        }
        let statement = try prepare("DELETE FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, index: 1, statement: statement)
        try step(statement)
    }

    public func record(for id: UUID) throws -> ScreenshotHistoryEntry? {
        let statement = try prepare("SELECT id, timestamp, mode, path, width, height, window_title, application_name, capture_settings, display_count FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, index: 1, statement: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw currentError() }
        return try decode(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer { guard let db = connection.handle else { throw StoreError.database("database is closed") }; var statement: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw currentError() }; return statement }

    private func bind(_ record: CaptureRecord, to statement: OpaquePointer) throws {
        try bindText(record.id.uuidString, index: 1, statement: statement)
        try bindDouble(record.timestamp.timeIntervalSince1970, index: 2, statement: statement)
        try bindText(record.mode.rawValue, index: 3, statement: statement)
        try bindText(record.path, index: 4, statement: statement)
        try bindInt32(Int32(record.width), index: 5, statement: statement)
        try bindInt32(Int32(record.height), index: 6, statement: statement)
        try bindOptionalText(record.windowTitle, index: 7, statement: statement)
        try bindOptionalText(record.applicationName, index: 8, statement: statement)
        let options = try record.captureSettings.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try bindOptionalText(options, index: 9, statement: statement)
        try bindOptionalText(record.displayCount.map(String.init), index: 10, statement: statement)
    }

    private func decode(_ statement: OpaquePointer) throws -> ScreenshotHistoryEntry {
        guard let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))), let mode = CaptureMode(rawValue: String(cString: sqlite3_column_text(statement, 2))) else { throw StoreError.database("invalid stored record") }
        let path = String(cString: sqlite3_column_text(statement, 3))
        let options = try optionalText(statement, 8).map { try JSONDecoder().decode(CaptureSettings.self, from: Data($0.utf8)) }
        let displays = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 9))
        let record = CaptureRecord(id: id, timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), mode: mode, path: path, width: Int(sqlite3_column_int(statement, 4)), height: Int(sqlite3_column_int(statement, 5)), windowTitle: optionalText(statement, 6), applicationName: optionalText(statement, 7), captureSettings: options, displayCount: displays)
        return ScreenshotHistoryEntry(record: record, isMissing: !FileManager.default.fileExists(atPath: path))
    }

    private static func createSchema(handle: OpaquePointer) throws {
        let sql = "CREATE TABLE IF NOT EXISTS screenshots (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, mode TEXT NOT NULL, path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, window_title TEXT, application_name TEXT)"
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.database(String(cString: sqlite3_errmsg(handle))) }
        // Existing installations keep all rows. Optional fields distinguish
        // historical records whose capture settings were never stored.
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(screenshots)", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.database(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw StoreError.database(String(cString: sqlite3_errmsg(handle))) }
            columns.insert(String(cString: sqlite3_column_text(statement, 1)))
        }
        for (column, type) in [("capture_settings", "TEXT"), ("display_count", "INTEGER")] where !columns.contains(column) {
            guard sqlite3_exec(handle, "ALTER TABLE screenshots ADD COLUMN \(column) \(type)", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.database(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func currentError() -> StoreError { guard let handle = connection.handle else { return .database("database is closed") }; return .database(String(cString: sqlite3_errmsg(handle))) }
    private func step(_ statement: OpaquePointer) throws { guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() } }
    private func bindText(_ value: String, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw currentError() } }
    private func bindOptionalText(_ value: String?, index: Int32, statement: OpaquePointer) throws { guard (value == nil ? sqlite3_bind_null(statement, index) : sqlite3_bind_text(statement, index, value!, -1, SQLITE_TRANSIENT)) == SQLITE_OK else { throw currentError() } }
    private func bindDouble(_ value: Double, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw currentError() } }
    private func bindInt32(_ value: Int32, index: Int32, statement: OpaquePointer) throws { guard sqlite3_bind_int(statement, index, value) == SQLITE_OK else { throw currentError() } }
    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? { guard let value = sqlite3_column_text(statement, index) else { return nil }; return String(cString: value) }
}

final class SQLiteConnectionHolder: @unchecked Sendable {
    private(set) var handle: OpaquePointer?
    init(handle: OpaquePointer) { self.handle = handle }
    func close() { if let handle { sqlite3_close(handle); self.handle = nil } }
    deinit { close() }
}

public enum StoreError: Error, LocalizedError, Sendable { case database(String); public var errorDescription: String? { if case .database(let message) = self { return message }; return nil } }

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
