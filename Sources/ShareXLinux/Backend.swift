import Foundation
import ShareXLinuxCore

struct DesktopEntry: Encodable {
    var id: UUID
    var path: String
    var mode: String
    var timestamp: Date
    var width: Int
    var height: Int
    var isMissing: Bool
    var warning: String?

    init(_ record: LinuxCaptureRecord, missing: Bool = false, warning: String? = nil) {
        id = record.id
        path = record.path
        mode = record.mode.rawValue
        timestamp = record.timestamp
        width = record.width
        height = record.height
        isMissing = missing
        self.warning = warning
    }
}

struct Backend: Sendable {
    let executable: URL
    let desktop: URL
    let paths = LinuxPaths()
    private var preferences: LinuxSettingsStore { LinuxSettingsStore(fileURL: paths.settingsURL) }

    func run(_ arguments: [String]) async throws {
        let value = arguments.count == 2 ? arguments[1] : nil
        switch (arguments.first ?? "", arguments.count) {
        case ("settings", 1):
            try respond(settings())
        case ("saveSettings", 1):
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let candidate = try JSONDecoder().decode(LinuxAppSettings.self, from: data).validated()
            try savePreferences(candidate)
            try respond(settings())
        case ("capture", 2):
            guard let mode = LinuxCaptureMode(rawValue: arguments[1]) else { throw invalidArguments }
            let service = LinuxCaptureService(portalHelper: desktop.appendingPathComponent("portal_capture.py"))
            let workflow = LinuxAppController(capture: { try await service.capture(mode: $0, settings: $1, temporaryDirectory: $2) },
                                              resize: resize,
                                              insert: { try await history().insert($0) },
                                              copyImage: { try await LinuxClipboardService().copyImage(url: $0) })
            let saved = try await workflow.capture(mode, settings: settings().capture)
            try respond(DesktopEntry(saved.record, warning: saved.warning))
        case ("history", 1), ("history", 2):
            let entries = try await history().list(search: value)
            try respond(entries.map { DesktopEntry($0.record, missing: $0.isMissing) })
        case ("delete", 2):
            guard let id = UUID(uuidString: arguments[1]) else { throw invalidArguments }
            try await history().delete(id: id, removeFile: true)
            try respond(true)
        case ("ocr", 2):
            let text = try await LinuxOCRService().recognize(image: URL(fileURLWithPath: arguments[1]),
                                                             settings: settings().ocr, resize: resize)
            try respond(text)
        case ("languages", 1):
            try await respond(LinuxOCRService().languages())
        case ("copyImage", 2):
            try await LinuxClipboardService().copyImage(url: URL(fileURLWithPath: arguments[1]))
            try respond(true)
        case ("copyText", 1):
            let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            if !text.isEmpty { try await LinuxClipboardService().copyText(text) }
            try respond(true)
        default: throw invalidArguments
        }
    }

    private var invalidArguments: LinuxSupportError { .unsupported("Invalid ShareX desktop action or arguments.") }

    private func respond<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        FileHandle.standardOutput.write(try encoder.encode(value))
    }

    private func settings() -> LinuxAppSettings {
        var result = preferences.load()
        if result.capture.screenshotFolderPath.isEmpty { result.capture.screenshotFolderPath = paths.defaultScreenshotFolder.path }
        result.launchAtLogin = FileManager.default.fileExists(atPath: paths.autostartURL.path)
        return result
    }

    private func savePreferences(_ candidate: LinuxAppSettings) throws {
        let previous = settings()
        if previous.launchAtLogin != candidate.launchAtLogin { try setAutostart(candidate.launchAtLogin) }
        do { try preferences.save(candidate) }
        catch {
            if previous.launchAtLogin != candidate.launchAtLogin { try setAutostart(previous.launchAtLogin) }
            throw error
        }
    }

    private func setAutostart(_ enabled: Bool) throws {
        let url = paths.autostartURL
        if !enabled {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let path = executable.path
        guard !path.contains(where: \.isNewline) else { throw LinuxSupportError.unsupported("Launch at login requires an executable path without newlines.") }
        // Desktop entry escaping is applied after Exec quoting. Percent signs are field codes.
        let quoted = path.reduce(into: "") { text, char in
            if "\"`$\\".contains(char) { text.append("\\") }
            text.append(char)
        }.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "%%")
        let entry = "[Desktop Entry]\nType=Application\nName=ShareX Linux\nExec=\"\(quoted)\" --autostart\nTerminal=false\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(entry.utf8).write(to: url, options: .atomic)
    }

    private func history() throws -> LinuxScreenshotStore {
        try LinuxScreenshotStore(databaseURL: paths.databaseURL)
    }

    private func resize(_ source: URL, _ width: Int, _ height: Int, _ directory: URL) async throws -> URL {
        let target = directory.appendingPathComponent("resized.png")
        try await LinuxProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                                           arguments: [desktop.appendingPathComponent("image_scale.py").path, source.path,
                                                       String(width), String(height), target.path])
        return target
    }
}
