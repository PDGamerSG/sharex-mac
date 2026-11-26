import Foundation
import ShareXLinuxCore
import Testing

struct LinuxSettingsStoreTests {
    @Test("XDG paths use supplied environment values")
    func xdgPaths() throws {
        let paths = LinuxPaths(environment: ["HOME": "/home/alice", "XDG_CONFIG_HOME": "/config", "XDG_DATA_HOME": "/data"])
        #expect(paths.settingsURL.path == "/config/sharex/sharex-linux.json")
        #expect(paths.databaseURL.path == "/data/sharex/history.sqlite")
        #expect(paths.defaultScreenshotFolder.path == "/home/alice/Pictures/ShareX")
    }

    @Test("missing Linux settings load defaults and saved values round trip")
    func persistence() throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let url = directory.url.appendingPathComponent("settings.json")
        let store = LinuxSettingsStore(fileURL: url)
        #expect(store.load() == LinuxAppSettings())
        var settings = LinuxAppSettings()
        settings.capture.delaySeconds = 12
        settings.startHidden = true
        try store.save(settings)
        #expect(LinuxSettingsStore(fileURL: url).load() == settings)
    }
}
