import Foundation
import Testing
@testable import ShareXMacCore

@Suite("History view model")
struct HistoryViewModelTests {
    @Test("refresh retains filename search and confirmed delete removes the file")
    @MainActor func refreshAndDeleteExistingFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SQLiteScreenshotStore(databaseURL: folder.appendingPathComponent("history.sqlite"))
        let path = folder.appendingPathComponent("Selected.png")
        try Data([1, 2, 3]).write(to: path)
        let record = CaptureRecord(mode: .region, path: path.path, width: 2, height: 2)
        try await store.insert(record)
        try await store.insert(CaptureRecord(mode: .region, path: folder.appendingPathComponent("Other.png").path, width: 1, height: 1))
        let model = HistoryViewModel(store: store)
        await model.reload(search: "selected")
        await model.refresh()
        #expect(model.entries.map(\.id) == [record.id])
        #expect(model.entries.first?.isMissing == false)
        model.requestDelete(model.entries[0])
        model.cancelDelete()
        #expect(FileManager.default.fileExists(atPath: path.path))
        model.requestDelete(model.entries[0])
        await model.confirmDelete()
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(model.entries.isEmpty)
        #expect(try await store.list().count == 1)
    }

    @Test("search preserves missing files and deletion requires explicit confirmation")
    @MainActor func searchAndDelete() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SQLiteScreenshotStore(databaseURL: folder.appendingPathComponent("history.sqlite"))
        let record = CaptureRecord(mode: .region, path: folder.appendingPathComponent("Search.png").path, width: 2, height: 2)
        try await store.insert(record)
        let model = HistoryViewModel(store: store)
        await model.reload(search: "search")
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.isMissing == true)
        model.requestDelete(model.entries[0])
        #expect(try await store.list().count == 1)
        model.cancelDelete()
        await model.confirmDelete()
        #expect(try await store.list().count == 1)
        model.requestDelete(model.entries[0])
        await model.confirmDelete()
        #expect(model.entries.isEmpty)
        #expect(try await store.list().isEmpty)
    }
}
