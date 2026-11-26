import Foundation
import ShareXCore

/// Linux-facing history API. The stored schema is shared with the macOS core,
/// while this wrapper retains Linux model names and metadata compatibility.
public actor LinuxScreenshotStore {
    private let store: SQLiteScreenshotStore

    public init(databaseURL: URL) throws {
        store = try SQLiteScreenshotStore(databaseURL: databaseURL, createParentDirectory: true)
    }

    public func close() async {
        await store.close()
    }

    public func insert(_ record: LinuxCaptureRecord) async throws {
        try await store.insert(record.portableRecord)
    }

    public func list(search: String? = nil) async throws -> [LinuxScreenshotHistoryEntry] {
        let entries = try await store.list(search: search)
        return entries.map { $0.linuxEntry }
    }

    public func record(for id: UUID) async throws -> LinuxScreenshotHistoryEntry? {
        guard let entry = try await store.record(for: id) else { return nil }
        return entry.linuxEntry
    }

    public func delete(id: UUID, removeFile: Bool) async throws {
        try await store.delete(id: id, removeFile: removeFile)
    }
}

public typealias LinuxStoreError = StoreError

private extension LinuxCaptureRecord {
    var portableRecord: CaptureRecord {
        CaptureRecord(id: id, timestamp: timestamp, mode: CaptureMode(rawValue: mode.rawValue) ?? .fullscreen,
                      path: path, width: width, height: height, windowTitle: windowTitle,
                      applicationName: applicationName, captureSettings: captureSettings,
                      displayCount: displayCount)
    }
}

private extension ScreenshotHistoryEntry {
    var linuxEntry: LinuxScreenshotHistoryEntry {
        LinuxScreenshotHistoryEntry(
            record: LinuxCaptureRecord(id: record.id, timestamp: record.timestamp,
                                       mode: LinuxCaptureMode(rawValue: record.mode.rawValue) ?? .fullscreen,
                                       path: record.path, width: record.width, height: record.height,
                                       windowTitle: record.windowTitle, applicationName: record.applicationName,
                                       captureSettings: record.captureSettings, displayCount: record.displayCount),
            isMissing: isMissing
        )
    }
}
