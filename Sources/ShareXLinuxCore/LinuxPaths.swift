import Foundation

public struct LinuxPaths: Sendable {
    public let settingsURL: URL
    public let databaseURL: URL
    public let defaultScreenshotFolder: URL
    public let autostartURL: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = URL(fileURLWithPath: environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path)
        func directory(_ variable: String, fallback: String) -> URL {
            if let value = environment[variable], value.hasPrefix("/") { return URL(fileURLWithPath: value) }
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        let config = directory("XDG_CONFIG_HOME", fallback: ".config")
        settingsURL = config.appendingPathComponent("sharex/sharex-linux.json")
        databaseURL = directory("XDG_DATA_HOME", fallback: ".local/share").appendingPathComponent("sharex/history.sqlite")
        autostartURL = config.appendingPathComponent("autostart/io.github.PDGamerSG.ShareXLinux.desktop")
        let userDirs = (try? String(contentsOf: config.appendingPathComponent("user-dirs.dirs"), encoding: .utf8)) ?? ""
        let pictures = userDirs.components(separatedBy: .newlines).compactMap { line -> URL? in
            let prefix = "XDG_PICTURES_DIR=\""
            guard line.hasPrefix(prefix), line.hasSuffix("\"") else { return nil }
            let value = String(line.dropFirst(prefix.count).dropLast())
            if value == "$HOME" { return home }
            if value.hasPrefix("$HOME/") { return home.appendingPathComponent(String(value.dropFirst(6))) }
            return value.hasPrefix("/") ? URL(fileURLWithPath: value) : nil
        }.first ?? home.appendingPathComponent("Pictures")
        defaultScreenshotFolder = pictures.appendingPathComponent("ShareX", isDirectory: true)
    }
}
