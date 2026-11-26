import Foundation

public struct LinuxOCRService: Sendable {
    private let runner: LinuxProcessRunner
    public init(runner: LinuxProcessRunner = LinuxProcessRunner()) { self.runner = runner }

    public func languages() async throws -> [String] {
        let result = try await runner.run(name: "tesseract", arguments: ["--list-langs"])
        return Self.parseLanguages(result.output.isEmpty ? result.errorOutput : result.output)
    }

    public func recognize(image: URL, settings: LinuxOCRSettings, resize: LinuxAppController.Resize) async throws -> String {
        let size = try LinuxPNGMetadata.read(url: image)
        let scale = settings.recognitionScale
        guard (1...4).contains(scale), Double(size.width) * Double(size.height) * scale * scale <= 64_000_000 else {
            throw LinuxSupportError.unsupported("Choose a smaller OCR region or reduce recognition scale in Settings.")
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ShareXOCR-\(UUID())")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let source = scale == 1 ? image : try await resize(image, Int(ceil(Double(size.width) * scale)),
                                                           Int(ceil(Double(size.height) * scale)), staging)
        var arguments = [source.path, "stdout"]
        if !settings.languages.isEmpty {
            let installed = try await Set(languages())
            let missing = settings.languages.filter { !installed.contains($0) }
            guard missing.isEmpty else {
                throw LinuxSupportError.unsupported("Install the Tesseract language data for \(missing.joined(separator: ", ")), or change OCR languages in Settings.")
            }
            arguments += ["-l", settings.languages.joined(separator: "+")]
        }
        if !settings.usesLanguageCorrection {
            arguments += ["-c", "load_system_dawg=0", "-c", "load_freq_dawg=0"]
        }
        return try await runner.run(name: "tesseract", arguments: arguments).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseLanguages(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "osd" && !$0.lowercased().hasPrefix("list of available languages") }.sorted()
    }
}
