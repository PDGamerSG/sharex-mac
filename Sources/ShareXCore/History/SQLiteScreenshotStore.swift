import Foundation
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

public actor SQLiteScreenshotStore: ScreenshotStore {
    private static let recordColumns = "id, timestamp, mode, path, width, height, window_title, application_name, capture_settings, display_count"
    private let connection: SQLiteConnectionHolder

    public init(databaseURL: URL, createParentDirectory: Bool = false) throws {
        if createParentDirectory {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(database)
            throw StoreError.database(message)
        }
        connection = SQLiteConnectionHolder(handle: database)
        // Each CLI action can open its own connection while the desktop app runs.
        sqlite3_busy_timeout(database, 5_000)
        do {
            try Self.createSchema(in: database)
        } catch {
            connection.close()
            throw error
        }
    }

    public func close() {
        connection.close()
    }

    public func insert(_ record: CaptureRecord) throws {
        let statement = try prepare("INSERT INTO screenshots (\(Self.recordColumns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try check(sqlite3_bind_double(statement, 2, record.timestamp.timeIntervalSince1970))
        try bindText(record.mode.rawValue, at: 3, to: statement)
        try bindText(record.path, at: 4, to: statement)
        try check(sqlite3_bind_int64(statement, 5, Int64(record.width)))
        try check(sqlite3_bind_int64(statement, 6, Int64(record.height)))
        try bindText(record.windowTitle, at: 7, to: statement)
        try bindText(record.applicationName, at: 8, to: statement)
        let settings = try record.captureSettings.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try bindText(settings, at: 9, to: statement)
        if let displayCount = record.displayCount {
            try check(sqlite3_bind_int64(statement, 10, Int64(displayCount)))
        }
        try stepToEnd(statement)
    }

    public func list(search: String? = nil) throws -> [ScreenshotHistoryEntry] {
        let statement = try prepare("SELECT \(Self.recordColumns) FROM screenshots ORDER BY timestamp DESC, rowid DESC")
        defer { sqlite3_finalize(statement) }
        var result: [ScreenshotHistoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw currentError() }
            let entry = try decode(statement)
            if let search, !search.isEmpty, !entry.record.fileURL.lastPathComponent.localizedCaseInsensitiveContains(search) {
                continue
            }
            result.append(entry)
        }
    }

    public func record(for id: UUID) throws -> ScreenshotHistoryEntry? {
        let statement = try prepare("SELECT \(Self.recordColumns) FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, at: 1, to: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw currentError() }
        return try decode(statement)
    }

    public func delete(id: UUID, removeFile: Bool) throws {
        if removeFile, let entry = try record(for: id) {
            do {
                try FileManager.default.removeItem(atPath: entry.record.path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // A missing image still has a removable history row.
            }
        }
        let statement = try prepare("DELETE FROM screenshots WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, at: 1, to: statement)
        try stepToEnd(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database = connection.handle else { throw StoreError.database("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw currentError()
        }
        return statement
    }

    private func decode(_ statement: OpaquePointer) throws -> ScreenshotHistoryEntry {
        guard let id = text(in: statement, at: 0).flatMap(UUID.init(uuidString:)),
              let mode = text(in: statement, at: 2).flatMap(CaptureMode.init(rawValue:)),
              let path = text(in: statement, at: 3) else {
            throw StoreError.database("invalid stored record")
        }
        let settings = try text(in: statement, at: 8).map { try JSONDecoder().decode(CaptureSettings.self, from: Data($0.utf8)) }
        let displayCount = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 9))
        let record = CaptureRecord(
            id: id, timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), mode: mode, path: path,
            width: Int(sqlite3_column_int64(statement, 4)), height: Int(sqlite3_column_int64(statement, 5)),
            windowTitle: text(in: statement, at: 6), applicationName: text(in: statement, at: 7),
            captureSettings: settings, displayCount: displayCount
        )
        return ScreenshotHistoryEntry(record: record, isMissing: !FileManager.default.fileExists(atPath: path))
    }

    private func currentError() -> StoreError {
        guard let database = connection.handle else { return .database("database is closed") }
        return .database(String(cString: sqlite3_errmsg(database)))
    }

    private func stepToEnd(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func check(_ status: Int32) throws {
        guard status == SQLITE_OK else { throw currentError() }
    }

    private func bindText(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        if let value {
            try check(sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT))
        } else {
            try check(sqlite3_bind_null(statement, index))
        }
    }

    private func text(in statement: OpaquePointer, at column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func createSchema(in database: OpaquePointer) throws {
        func execute(_ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.database(String(cString: sqlite3_errmsg(database)))
            }
        }
        // Take the write lock before reading columns so two first launches or
        // upgrades cannot both decide to add the same column.
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS screenshots (
                    id TEXT PRIMARY KEY, timestamp REAL NOT NULL, mode TEXT NOT NULL, path TEXT NOT NULL,
                    width INTEGER NOT NULL, height INTEGER NOT NULL, window_title TEXT, application_name TEXT,
                    capture_settings TEXT, display_count INTEGER
                )
                """)
            let columns = try existingColumns(in: database)
            for (name, type) in [("capture_settings", "TEXT"), ("display_count", "INTEGER")] where !columns.contains(name) {
                try execute("ALTER TABLE screenshots ADD COLUMN \(name) \(type)")
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private static func existingColumns(in database: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(screenshots)", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return columns }
            guard status == SQLITE_ROW, let name = sqlite3_column_text(statement, 1) else {
                throw StoreError.database(String(cString: sqlite3_errmsg(database)))
            }
            columns.insert(String(cString: name))
        }
    }
}

// The actor exclusively owns the handle. The holder also closes it when
// initialization fails or the actor is released without an explicit close.
package final class SQLiteConnectionHolder: @unchecked Sendable {
    private(set) var handle: OpaquePointer?

    package init(handle: OpaquePointer) { self.handle = handle }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    deinit { close() }
}

public enum StoreError: Error, LocalizedError, Equatable, Sendable {
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .database(let message): message
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
