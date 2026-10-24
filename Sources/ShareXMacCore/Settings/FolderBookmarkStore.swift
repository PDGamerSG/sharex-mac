import Foundation

public struct FolderBookmarkStore: Sendable {
    public struct Resolution: Sendable {
        public let url: URL
        public let isStale: Bool
        public let refreshedBookmarkData: Data?

        public init(url: URL, isStale: Bool, refreshedBookmarkData: Data?) {
            self.url = url
            self.isStale = isStale
            self.refreshedBookmarkData = refreshedBookmarkData
        }
    }

    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ data: Data) throws -> URL {
        try resolveWithStatus(data).url
    }

    public func resolveWithStatus(_ data: Data) throws -> Resolution {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let refreshed = isStale ? try makeBookmark(for: url) : nil
        return Resolution(url: url, isStale: isStale, refreshedBookmarkData: refreshed)
    }

    public func withSecurityScopedAccess<T>(to data: Data, _ body: (URL) throws -> T) throws -> T {
        let url = try resolveWithStatus(data).url
        return try Self.withAccess(to: url, start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() }, body)
    }

    static func withAccess<T>(to url: URL, start: (URL) -> Bool, stop: (URL) -> Void, _ body: (URL) throws -> T) rethrows -> T {
        let didStart = start(url)
        defer {
            if didStart { stop(url) }
        }
        return try body(url)
    }
}
