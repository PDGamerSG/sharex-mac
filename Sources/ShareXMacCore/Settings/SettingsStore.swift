import Foundation

public final class SettingsStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let fileURL: URL

    public init(userDefaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.userDefaults = userDefaults
        if let fileURL {
            self.fileURL = fileURL
        } else if let storedPath = userDefaults.string(forKey: "ShareXMac.settings.fileURL") {
            self.fileURL = URL(fileURLWithPath: storedPath)
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ShareXMac", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("settings.json")
        }
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: [.atomic])
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        userDefaults.set(fileURL.path, forKey: "ShareXMac.settings.fileURL")
    }
}
