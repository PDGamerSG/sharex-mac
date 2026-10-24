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

    @Test("overwriting existing settings preserves the replacement on reload")
    func overwriteSettingsReload() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: fileURL)
        try store.save(AppSettings(capture: CaptureSettings(delaySeconds: 1)))
        let replacement = AppSettings(capture: CaptureSettings(showCursor: true, delaySeconds: 9))

        try store.save(replacement)

        #expect(store.load() == replacement)
    }

    @Test("saved path is reused through injected defaults")
    func persistedPathFromDefaults() throws {
        let directory = try TemporaryDirectory()
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.path.\(UUID().uuidString)")!
        let fileURL = directory.url.appendingPathComponent("settings.json")
        let settings = AppSettings(capture: CaptureSettings(showCursor: true, delaySeconds: 8))

        try SettingsStore(userDefaults: defaults, fileURL: fileURL).save(settings)

        #expect(SettingsStore(userDefaults: defaults).load() == settings)
    }

    @Test("save failure before temporary creation leaves no settings files")
    func saveFailureBeforeTemporaryCreation() throws {
        let directory = try TemporaryDirectory()
        let parentFile = directory.url.appendingPathComponent("parent")
        try Data("file".utf8).write(to: parentFile)
        let fileURL = parentFile.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: fileURL)

        #expect(throws: Error.self) { try store.save(AppSettings()) }
        #expect(try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("settings.json") }.isEmpty)
    }

    @Test("replacement failure preserves destination and cleans temporary file")
    func replacementFailureCleansTemporaryFile() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("settings.json")
        let original = AppSettings(capture: CaptureSettings(delaySeconds: 2))
        let replacement = AppSettings(capture: CaptureSettings(showCursor: true, delaySeconds: 7))
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.replace.\(UUID().uuidString)")!
        let initialStore = SettingsStore(userDefaults: defaults, fileURL: fileURL)
        try initialStore.save(original)
        let failingStore = SettingsStore(userDefaults: defaults, fileURL: fileURL, replaceItem: { _, _ in throw ReplacementError() })

        #expect(throws: ReplacementError.self) { try failingStore.save(replacement) }
        #expect(failingStore.load() == original)
        #expect(try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".settings.json.") }.isEmpty)
    }

    @Test("folder bookmarks round trip through security scoped bookmark data")
    func bookmarkRoundTrip() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let store = FolderBookmarkStore()

        let bookmark = try store.makeBookmark(for: folder)
        let resolution = try store.resolveWithStatus(bookmark)
        let resolved = try store.resolve(bookmark)

        #expect(resolved.standardizedFileURL == folder.standardizedFileURL)
        #expect(resolution.url.standardizedFileURL == folder.standardizedFileURL)
        #expect(resolution.isStale == false)
        #expect(resolution.refreshedBookmarkData == nil)
    }

    @Test("scoped access helper invokes the closure with the resolved URL")
    func scopedAccessHelper() throws {
        let directory = try TemporaryDirectory()
        let store = FolderBookmarkStore()
        let bookmark = try store.makeBookmark(for: directory.url)
        var invoked = false

        let result = try store.withSecurityScopedAccess(to: bookmark) { url in
            invoked = true
            return url.standardizedFileURL
        }

        #expect(invoked)
        #expect(result == directory.url.standardizedFileURL)
    }

    @Test("scoped access is stopped after success and errors only when started")
    func scopedAccessLifecycle() throws {
        let url = URL(fileURLWithPath: "/tmp")
        var events: [String] = []
        let value = try FolderBookmarkStore.withAccess(to: url, start: { _ in events.append("start"); return true }, stop: { _ in events.append("stop") }) { _ in
            events.append("body")
            return 42
        }
        #expect(value == 42)
        #expect(events == ["start", "body", "stop"])

        events = []
        #expect(throws: AccessTestError.self) {
            try FolderBookmarkStore.withAccess(to: url, start: { _ in events.append("start"); return true }, stop: { _ in events.append("stop") }) { _ in
                events.append("body")
                throw AccessTestError()
            }
        }
        #expect(events == ["start", "body", "stop"])

        events = []
        _ = try FolderBookmarkStore.withAccess(to: url, start: { _ in false }, stop: { _ in events.append("stop") }) { _ in 42 }
        #expect(events.isEmpty)
    }

    @Test("moved folder bookmark reports status and refreshes stale data")
    func movedBookmarkStatus() throws {
        let directory = try TemporaryDirectory()
        let original = directory.url.appendingPathComponent("original", isDirectory: true)
        let moved = directory.url.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let store = FolderBookmarkStore()
        let bookmark = try store.makeBookmark(for: original)
        try FileManager.default.moveItem(at: original, to: moved)

        let result = try store.resolveWithStatus(bookmark)
        #expect(result.url.standardizedFileURL == moved.standardizedFileURL)
        #expect((result.refreshedBookmarkData != nil) == result.isStale)
        if let refreshed = result.refreshedBookmarkData {
            #expect(try store.resolveWithStatus(refreshed).isStale == false)
        }
    }

    @Test("malformed JSON loads defaults")
    func malformedSettings() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("settings.json")
        try Data("invalid json".utf8).write(to: file)
        #expect(SettingsStore(fileURL: file).load() == AppSettings())
    }
}

private struct AccessTestError: Error {}
private struct ReplacementError: Error {}

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
