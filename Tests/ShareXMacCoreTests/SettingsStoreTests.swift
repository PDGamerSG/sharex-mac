import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Settings persistence")
struct SettingsStoreTests {
    @Test("missing settings load the default values")
    func missingSettingsLoadDefaults() throws {
        let directory = try TemporaryDirectory()
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.missing.\(UUID().uuidString)")!
        let store = SettingsStore(userDefaults: defaults, fileURL: directory.url.appendingPathComponent("settings.json"))

        #expect(store.load() == AppSettings())
    }

    @Test("saved settings are loaded from the next store instance")
    func persistedSettingsReload() throws {
        let directory = try TemporaryDirectory()
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.persisted.\(UUID().uuidString)")!
        let fileURL = directory.url.appendingPathComponent("settings.json")
        let settings = AppSettings(capture: CaptureSettings(showCursor: true, delaySeconds: 4.5), ocr: OCRSettings(recognitionScale: 2, languages: ["en-US"], usesLanguageCorrection: false))

        try SettingsStore(userDefaults: defaults, fileURL: fileURL).save(settings)
        let reloaded = SettingsStore(userDefaults: defaults, fileURL: fileURL).load()

        #expect(reloaded == settings)
    }

    @Test("folder bookmarks round trip through security scoped bookmark data")
    func bookmarkRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let store = FolderBookmarkStore()

        let bookmark = try store.makeBookmark(for: folder)
        let resolved = try store.resolve(bookmark)

        #expect(resolved.standardizedFileURL == folder.standardizedFileURL)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXMacCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
