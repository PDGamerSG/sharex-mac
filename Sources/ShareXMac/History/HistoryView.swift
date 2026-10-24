import SwiftUI
import ShareXMacCore

enum HistoryAction { case preview, open, reveal, copyPath, ocr }

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    let onAction: (HistoryAction, ScreenshotHistoryEntry) -> Void

    var body: some View {
        HistoryContentView(model: model, showsImages: false, onAction: onAction)
    }
}

/// Both presentations use the same selection, search, actions, and confirmation.
struct HistoryContentView: View {
    @ObservedObject var model: HistoryViewModel
    let showsImages: Bool
    let onAction: (HistoryAction, ScreenshotHistoryEntry) -> Void
    @ViewState<String> private var search = ""
    @ViewState<UUID?> private var selection: UUID?

    private var selectedEntry: ScreenshotHistoryEntry? {
        model.entries.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search filenames", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search screenshot filenames")
                Button { Task { await model.reload(search: search) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh history and missing-file status")
            }
            .padding()
            Divider()
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
            }
            if model.entries.isEmpty {
                VStack(spacing: 12) {
                    if model.isLoading {
                        ProgressView("Loading history…")
                    } else {
                        Image(systemName: search.isEmpty ? "photo.on.rectangle" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(search.isEmpty ? "No screenshots yet" : "No matching screenshots")
                            .font(.headline)
                        Text(search.isEmpty ? "Saved captures appear here." : "Try another filename.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showsImages {
                imageGrid
            } else {
                metadataList
            }
            Divider()
            HStack {
                Text("\(model.entries.count) screenshot\(model.entries.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                if model.isLoading { ProgressView().controlSize(.small).accessibilityLabel("Refreshing history") }
                Spacer()
                Button("Preview") { perform(.preview) }
                    .disabled(selectedEntry == nil || selectedEntry?.isMissing == true)
                    .keyboardShortcut(.space, modifiers: [])
                Menu("Actions") {
                    if let entry = selectedEntry { HistoryActions(entry: entry, model: model, onAction: onAction) }
                }
                .disabled(selectedEntry == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 400)
        .task(id: search) {
            if !search.isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await model.reload(search: search)
        }
        .onChange(of: model.entries) { entries in
            if !entries.contains(where: { $0.id == selection }) { selection = nil }
        }
        .onDeleteCommand {
            if let entry = selectedEntry { model.requestDelete(entry) }
        }
        .alert("Delete screenshot?", isPresented: Binding(
            get: { model.pendingDelete != nil },
            // The buttons own cancellation. Dismissing the alert must not
            // clear the entry before the asynchronous delete starts.
            set: { _ in }
        )) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { Task { await model.confirmDelete() } }
        } message: {
            Text("\(model.pendingDelete.map { URL(fileURLWithPath: $0.record.path).lastPathComponent } ?? "This screenshot") will be deleted from disk and history. This cannot be undone.")
        }
    }

    private var metadataList: some View {
        List(selection: $selection) {
            ForEach(model.entries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.isMissing ? "exclamationmark.triangle" : "photo")
                        .foregroundStyle(entry.isMissing ? .orange : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: entry.record.path).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack {
                            Text(entry.record.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                            Text("· \(entry.record.mode.historyTitle) · \(entry.record.width) × \(entry.record.height)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            if let count = entry.record.displayCount {
                                Text("\(count) display\(count == 1 ? "" : "s")")
                            }
                            if let options = entry.record.captureSettings {
                                Text("Cursor \(options.showCursor ? "included" : "hidden") · Delay \(options.delaySeconds.formatted()) s")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let application = entry.record.applicationName { Text(application).font(.caption).foregroundStyle(.secondary) }
                        if let title = entry.record.windowTitle { Text(title).font(.caption).lineLimit(1) }
                        if entry.isMissing { Text("File missing").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .tag(entry.id)
                .contextMenu { HistoryActions(entry: entry, model: model, onAction: onAction) }
                .onTapGesture(count: 2) { if !entry.isMissing { onAction(.preview, entry) } }
            }
        }
    }

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176, maximum: 240), spacing: 16)], spacing: 16) {
                ForEach(model.entries) { entry in
                    Button { selection = entry.id } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HistoryThumbnail(entry: entry)
                                .frame(height: 128)
                                .frame(maxWidth: .infinity)
                            Text(URL(fileURLWithPath: entry.record.path).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.isMissing ? "File missing" : "\(entry.record.width) × \(entry.record.height)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.record.timestamp, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(selection == entry.id ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == entry.id ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == entry.id ? [.isSelected] : [])
                    .contextMenu { HistoryActions(entry: entry, model: model, onAction: onAction) }
                }
            }
            .padding(16)
        }
    }

    private func perform(_ action: HistoryAction) {
        if let entry = selectedEntry { onAction(action, entry) }
    }
}

private struct HistoryActions: View {
    let entry: ScreenshotHistoryEntry
    let model: HistoryViewModel
    let onAction: (HistoryAction, ScreenshotHistoryEntry) -> Void

    var body: some View {
        Group {
            Button("Preview") { onAction(.preview, entry) }
            Button("Open") { onAction(.open, entry) }
            Button("Reveal in Finder") { onAction(.reveal, entry) }
            Button("Recognize Text…") { onAction(.ocr, entry) }
        }
        .disabled(entry.isMissing)
        Button("Copy Path") { onAction(.copyPath, entry) }
        Divider()
        Button("Delete…", role: .destructive) { model.requestDelete(entry) }
    }
}

private extension CaptureMode {
    var historyTitle: String {
        switch self {
        case .fullscreen: return "Full Screen"
        case .region: return "Region"
        case .window: return "Window"
        case .ocrRegion: return "OCR Region"
        }
    }
}
