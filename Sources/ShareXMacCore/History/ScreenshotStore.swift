import Foundation

public struct ScreenshotHistoryEntry: Identifiable, Equatable, Sendable {
    public let record: CaptureRecord
    public let isMissing: Bool
    public var id: UUID { record.id }

    public init(record: CaptureRecord, isMissing: Bool) {
        self.record = record
        self.isMissing = isMissing
    }
}

public protocol ScreenshotStore: Sendable {
    func insert(_ record: CaptureRecord) async throws
    func list(search: String?) async throws -> [ScreenshotHistoryEntry]
    func delete(id: UUID, removeFile: Bool) async throws
    func record(for id: UUID) async throws -> ScreenshotHistoryEntry?
}

public extension ScreenshotStore {
    func list() async throws -> [ScreenshotHistoryEntry] { try await list(search: nil) }
}
