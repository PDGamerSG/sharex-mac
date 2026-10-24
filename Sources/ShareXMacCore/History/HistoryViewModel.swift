import Combine
import Foundation

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var entries: [ScreenshotHistoryEntry] = []
    @Published public private(set) var pendingDelete: ScreenshotHistoryEntry?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading = false
    private let store: any ScreenshotStore
    private var query: String?
    private var generation = 0

    public init(store: any ScreenshotStore) { self.store = store }

    public func refresh() async { await reload(search: query) }

    public func reload(search: String? = nil) async {
        query = search
        generation += 1
        let request = generation
        isLoading = true
        do {
            let result = try await store.list(search: search)
            guard request == generation else { return }
            entries = result
            errorMessage = nil
        } catch {
            guard request == generation else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func requestDelete(_ entry: ScreenshotHistoryEntry) { pendingDelete = entry }
    public func cancelDelete() { pendingDelete = nil }

    public func confirmDelete() async {
        guard let entry = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await store.delete(id: entry.id, removeFile: true)
            await reload(search: query)
        } catch { errorMessage = error.localizedDescription }
    }
}
