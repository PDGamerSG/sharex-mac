import SwiftUI
import ImageIO
import ShareXMacCore

struct ImageHistoryView: View {
    @ObservedObject var model: HistoryViewModel
    let onAction: (HistoryAction, ScreenshotHistoryEntry) -> Void

    var body: some View {
        HistoryContentView(model: model, showsImages: true, onAction: onAction)
    }
}

struct HistoryThumbnail: View {
    let entry: ScreenshotHistoryEntry
    @ViewState<CGImage?> private var thumbnail: CGImage?
    @ViewState<Bool> private var loaded = false

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if entry.isMissing || loaded {
                Image(systemName: entry.isMissing ? "exclamationmark.triangle" : "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityHidden(true)
        .task(id: "\(entry.record.path):\(entry.isMissing)") {
            thumbnail = nil
            loaded = false
            guard !entry.isMissing else { return }
            let image = await HistoryThumbnailCache.shared.image(at: entry.record.path)
            guard !Task.isCancelled else { return }
            thumbnail = image
            loaded = true
        }
    }
}

/// ImageIO creates only a bounded thumbnail. Actor isolation keeps file access
/// and decoding off MainActor and serializes work when many cells appear.
private actor HistoryThumbnailCache {
    static let shared = HistoryThumbnailCache()
    private let capacity = 48
    private var images: [String: CGImage] = [:]
    private var insertionOrder: [String] = []

    func image(at path: String) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let url = URL(fileURLWithPath: path)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(path):\(modified)"
        if let cached = images[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 384,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        if insertionOrder.count >= capacity { images.removeValue(forKey: insertionOrder.removeFirst()) }
        images[key] = image
        insertionOrder.append(key)
        return image
    }
}
