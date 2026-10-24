import AppKit
import Combine
import ImageIO
@preconcurrency import ScreenCaptureKit
import ShareXMacCore
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    let settingsModel: SettingsViewModel
    let imageHistoryModel: HistoryViewModel
    let databaseURL: URL
    @Published private(set) var folderURL: URL?
    private let store: SQLiteScreenshotStore
    private let bookmarks = FolderBookmarkStore()
    private let screenCapture = ScreenCaptureService()
    private let countdown = CaptureCountdown()
    private let confirmation = CaptureConfirmation()
    private var folderHasScope = false
    private var menu: MenuBarController?
    private var captureTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var imageHistoryWindow: AppWindow?
    private var settingsWindow: AppWindow?
    private var previewWindows: [AppWindow] = []
    private var ocrWindows: [UUID: OCRWindow] = [:]

    lazy var hotkeys = GlobalHotkeyManager { [weak self] action in self?.perform(action) }

    private lazy var captureCoordinator = CaptureCoordinator(
        store: store,
        settings: { [unowned self] in settingsModel.settings },
        hasPermission: { CGPreflightScreenCaptureAccess() },
        delay: { [unowned self] seconds in
            try await countdown.wait(seconds: seconds, onCancel: { [weak self] in self?.captureTask?.cancel() })
        },
        takeImage: { [unowned self] mode, options in try await takeImage(mode: mode, options: options) },
        writeImage: { [unowned self] image, date in
            guard let folder = folderURL else { throw AppError.folderRequired }
            return try await Task.detached(priority: .userInitiated) {
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                return try CaptureFileWriter().writePNG(image, to: folder, date: date)
            }.value
        },
        copyFileToClipboard: { [unowned self] url in copyImageFileToClipboard(url) },
        onSaved: { [unowned self] record in confirmation.show(record: record) })

    init() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShareXMac", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        databaseURL = support.appendingPathComponent("history.sqlite")
        store = try SQLiteScreenshotStore(databaseURL: databaseURL)
        imageHistoryModel = HistoryViewModel(store: store)
        let settings = SettingsStore()
        settingsModel = SettingsViewModel(settings: settings.load(), save: settings.save)
    }

    func start() {
        menu = MenuBarController(onAction: { [weak self] in self?.perform($0) })
        menu?.updateShortcuts(settingsModel.settings.hotkeys)
        restoreFolder()
        settingsObservation = settingsModel.$settings.sink { [weak self] updated in
            guard let self else { return }
            self.menu?.updateShortcuts(updated.hotkeys)
            do { try self.hotkeys.register(updated.hotkeys) }
            catch { self.showError("Shortcuts could not be updated", error: error) }
        }
        // The picker is explicit on first launch; a cancelled picker can be
        // reopened from Settings or when starting the next capture.
        if folderURL == nil { chooseScreenshotFolder() }
        if !UserDefaults.standard.bool(forKey: "ShareXMac.startHidden") { showSettings() }
    }

    func stop() {
        captureTask?.cancel()
        countdown.close()
        confirmation.close()
        hotkeys.unregisterAll()
        settingsObservation?.cancel()
        if folderHasScope { folderURL?.stopAccessingSecurityScopedResource() }
        folderHasScope = false
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .fullscreen: beginCapture(.fullscreen)
        case .region: beginCapture(.region)
        case .window: beginCapture(.window)
        case .ocrRegion: beginCapture(.ocrRegion)
        case .history: break // Legacy settings can decode this value, but it is no longer registered.
        case .imageHistory: showImageHistory()
        case .settings: showSettings()
        }
    }

    private func beginCapture(_ mode: CaptureMode) {
        guard captureTask == nil else { return }
        if folderURL == nil { chooseScreenshotFolder() }
        guard folderURL != nil else { return }
        guard CGPreflightScreenCaptureAccess() else { showPermissionGuidance(); return }
        menu?.setCapturing(true)
        // Keep our settings/history out of screenshots and leave the desktop
        // unobstructed before the delay and selection begin.
        NSApp.hide(nil)
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                captureTask = nil
                menu?.setCapturing(false)
            }
            let result = await captureCoordinator.capture(mode)
            switch result {
            case .success(let record):
                await refreshHistory()
                if mode == .ocrRegion { openOCR(record) }
            case .failure(.cancelled), .failure(.busy): break
            case .failure(.permissionRequired): showPermissionGuidance()
            case .failure(let error): showError("Screenshot could not be completed", error: error)
            }
        }
    }

    private func takeImage(mode: CaptureMode, options: CaptureSettings) async throws -> CapturedImage? {
        // Allow the menu/countdown's removal to reach the window server.
        try await Task.sleep(nanoseconds: 180_000_000)
        switch mode {
        case .fullscreen:
            let desktop = try await screenCapture.captureDesktop(showCursor: options.showCursor)
            return CapturedImage(image: desktop.image, displayCount: desktop.displayCount)
        case .region, .ocrRegion:
            let frozen = try await screenCapture.captureDesktop(showCursor: options.showCursor)
            let currentBounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
            guard currentBounds == frozen.geometry.appKitBounds else { throw AppError.displaysChanged }
            guard let region = await RegionSelectionPanel().select(image: frozen.image, screenBounds: frozen.geometry.appKitBounds) else { return nil }
            guard let image = frozen.crop(appKitRegion: region) else { throw AppError.emptyRegion }
            return CapturedImage(image: image, displayCount: frozen.displayCount)
        case .window:
            guard let window = try await WindowPickerPanel().selectWindow() else { return nil }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 120_000_000)
            let image = try await screenCapture.captureWindow(window, showCursor: options.showCursor)
            return CapturedImage(image: image, windowTitle: window.title, applicationName: window.owningApplication?.applicationName)
        }
    }

    private func restoreFolder() {
        guard let data = settingsModel.settings.screenshotFolderBookmark else { return }
        do {
            let resolution = try bookmarks.resolveWithStatus(data)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolution.url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw AppError.folderUnavailable }
            if let refreshed = resolution.refreshedBookmarkData {
                guard settingsModel.update({ $0.screenshotFolderBookmark = refreshed }) else { throw AppError.folderUnavailable }
            }
            activateFolder(resolution.url)
        } catch { showError("Choose your screenshot folder again", error: error) }
    }

    func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.message = "Screenshots are saved here as PNG files. History stays on this Mac."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let suggested = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShareX", isDirectory: true)
        try? FileManager.default.createDirectory(at: suggested, withIntermediateDirectories: true)
        panel.directoryURL = folderURL ?? suggested
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try bookmarks.makeBookmark(for: url)
            guard settingsModel.update({ $0.screenshotFolderBookmark = data }) else {
                throw AppError.settings(settingsModel.errorMessage ?? "Settings could not be saved.")
            }
            activateFolder(url)
        } catch { showError("Screenshot folder could not be saved", error: error) }
    }

    private func activateFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        if folderHasScope { folderURL?.stopAccessingSecurityScopedResource() }
        folderURL = url
        folderHasScope = accessed
    }

    private func showImageHistory() {
        if imageHistoryWindow == nil {
            imageHistoryWindow = AppWindow(title: "Image History", size: NSSize(width: 960, height: 680),
                content: ImageHistoryView(model: imageHistoryModel, onAction: { [weak self] in self?.historyAction($0, entry: $1) }))
        }
        imageHistoryWindow?.present()
        Task { await refreshHistory() }
    }

    private func refreshHistory() async {
        await imageHistoryModel.refresh()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = AppWindow(title: "ShareX Mac Settings", size: NSSize(width: 720, height: 590),
                                      content: AppSettingsRoot(coordinator: self))
        }
        settingsWindow?.present()
    }

    private func historyAction(_ action: HistoryAction, entry: ScreenshotHistoryEntry) {
        let url = URL(fileURLWithPath: entry.record.path)
        switch action {
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        case .copyImage:
            copyImageFileToClipboard(url)
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open:
            if !NSWorkspace.shared.open(url) { showError("Image could not be opened", error: AppError.imageUnavailable) }
        case .ocr: openOCR(entry.record)
        case .preview:
            let window = AppWindow(title: url.lastPathComponent, size: NSSize(width: 820, height: 620), content: ScreenshotPreview(url: url))
            previewWindows.removeAll { $0.window?.isVisible != true }
            previewWindows.append(window)
            window.present()
        }
    }

    private func copyImageFileToClipboard(_ url: URL) {
        // Read the canonical PNG off the main actor, then publish it on the
        // main actor. Large Retina captures must not block menu-bar updates.
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                _ = NSPasteboard.general.setData(data, forType: .png)
            }
        }
    }

    private func openOCR(_ record: CaptureRecord) {
        let options = settingsModel.settings.ocr
        weak let weakCoordinator: AppCoordinator? = self
        Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: record.path) as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw AppError.imageUnavailable }
                    return image
                }.value
                let id = UUID()
                let window = OCRWindow(image: image, service: VisionOCRService(), settings: options)
                window.onClose = { [weak weakCoordinator] in weakCoordinator?.ocrWindows[id] = nil }
                ocrWindows[id] = window
                NSApp.activate(ignoringOtherApps: true)
                window.showWindow(nil)
                window.window?.makeKeyAndOrderFront(nil)
            } catch { showError("Text recognition could not start", error: error) }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showPermissionGuidance() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow screenshots in System Settings"
        alert.informativeText = "Enable ShareX Mac under Privacy & Security → Screen Recording (or Screen & System Audio Recording), then quit and reopen ShareX Mac. macOS uses this permission for still screenshots."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = CGRequestScreenCaptureAccess()
            openPrivacySettings()
        }
    }

    private func showError(_ title: String, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private enum AppError: Error, LocalizedError {
    case folderRequired, folderUnavailable, displaysChanged, emptyRegion, imageUnavailable, settings(String)
    var errorDescription: String? {
        switch self {
        case .folderRequired: return "Choose a screenshot folder in Settings."
        case .folderUnavailable: return "The saved folder is missing or cannot be accessed. Choose a writable screenshot folder in Settings."
        case .displaysChanged: return "The display arrangement changed during capture. Start the screenshot again."
        case .emptyRegion: return "The selected region has no pixels. Try selecting a larger area."
        case .imageUnavailable: return "The image is missing or could not be read. Check its location in Image History."
        case .settings(let message): return message
        }
    }
}

private struct AppSettingsRoot: View {
    @ObservedObject var coordinator: AppCoordinator
    var body: some View {
        SettingsView(model: coordinator.settingsModel, hotkeys: coordinator.hotkeys,
                     folderPath: coordinator.folderURL?.path ?? "",
                     databasePath: coordinator.databaseURL.path,
                     chooseFolder: { coordinator.chooseScreenshotFolder() },
                     openPrivacySettings: { coordinator.openPrivacySettings() })
    }
}

private struct ScreenshotPreview: View {
    let url: URL
    @ViewState private var image: NSImage?
    @ViewState private var failed = false
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(16).accessibilityLabel(url.lastPathComponent) }
            else if failed { Text("This image is missing or cannot be opened.").foregroundStyle(.secondary) }
            else { ProgressView("Loading preview…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let thumbnail = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }.value
            if let thumbnail { image = NSImage(cgImage: thumbnail, size: .zero) }
            else { failed = true }
        }
    }
}
