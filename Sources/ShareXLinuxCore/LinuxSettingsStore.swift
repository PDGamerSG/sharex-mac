import Foundation

public struct LinuxSettingsStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileURL = fileURL ?? LinuxPaths(environment: environment).settingsURL
    }

    public func load() -> LinuxAppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(LinuxAppSettings.self, from: data),
              let validated = try? settings.validated() else { return LinuxAppSettings() }
        return validated
    }

    public func save(_ settings: LinuxAppSettings) throws {
        let settings = try settings.validated()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
