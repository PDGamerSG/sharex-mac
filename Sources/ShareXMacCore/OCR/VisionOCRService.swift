import CoreGraphics
import Foundation
import Vision

public enum OCRError: Error, Equatable, LocalizedError, Sendable {
    case invalidImage
    case imageTooLarge
    case unsupportedLanguages([String])
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "The image could not be prepared for text recognition."
        case .imageTooLarge: return "The image is too large for text recognition. Choose a smaller region or lower the recognition scale."
        case .unsupportedLanguages(let languages): return "Text recognition does not support these languages: \(languages.joined(separator: ", ")). Choose a supported language in Settings."
        case .recognitionFailed(let reason): return "Text recognition failed: \(reason)"
        }
    }
}

public final class VisionOCRService: Sendable {
    /// Interactive OCR must return promptly for the result window. Vision's
    /// accurate mode can spend close to a minute compiling its model on a
    /// fresh macOS install, leaving the user with an apparently empty window.
    public static let interactiveRecognitionLevel: VNRequestTextRecognitionLevel = .fast

    public init() {}

    public static func supportedLanguages() throws -> [String] {
        try VisionOCRService().supportedLanguages()
    }

    public func supportedLanguages() throws -> [String] {
        let request = Self.makeRequest(settings: OCRSettings())
        do {
            return try request.supportedRecognitionLanguages().sorted()
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }
    }

    public func recognize(image: CGImage, settings: OCRSettings, singleLine: Bool = false) async throws -> String {
        try Task.checkCancellation()
        return try await OCRRecognitionOperation(image: image, settings: settings, singleLine: singleLine).value()
    }

    public func recognize(image: CGImage, language: String? = nil, scale: Double = 1, singleLine: Bool = false) async throws -> String {
        try await recognize(image: image, settings: OCRSettings(recognitionScale: scale, languages: language.map { [$0] } ?? []), singleLine: singleLine)
    }

    static func makeRequest(settings: OCRSettings) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = Self.interactiveRecognitionLevel
        request.usesLanguageCorrection = settings.usesLanguageCorrection
        request.automaticallyDetectsLanguage = settings.languages.isEmpty
        return request
    }
}

/// Vision performs synchronously on a background queue. The lock protects the
/// completion and current request; Vision explicitly permits request.cancel()
/// while a request is in progress, so cancellation need not wait for that queue.
private final class OCRRecognitionOperation: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "ShareXMac.VisionOCR", qos: .userInitiated)
    private let image: CGImage
    private let settings: OCRSettings
    private let singleLine: Bool
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var request: VNRecognizeTextRequest?

    init(image: CGImage, settings: OCRSettings, singleLine: Bool) {
        self.image = image
        self.settings = settings
        self.singleLine = singleLine
    }

    func value() async throws -> String {
        try await withTaskCancellationHandler {
            let cancelled = Task.isCancelled
            return try await withCheckedThrowingContinuation { continuation in
                if cancelled { cancel() }
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                Self.queue.async { self.perform() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        finish(.failure(CancellationError()), cancelRequest: true)
    }

    private func finish(_ result: Result<String, Error>, cancelRequest: Bool = false) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let request = self.request
        self.request = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if cancelRequest { request?.cancel() }
        continuation?.resume(with: result)
    }

    private func isFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    private func install(_ request: VNRecognizeTextRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else { return false }
        self.request = request
        return true
    }

    private func perform() {
        guard !isFinished() else { return }
        do {
            // Validate before model inference and before allocating a scaled bitmap.
            _ = try OCRImagePreparation.dimensions(width: image.width, height: image.height, scale: settings.recognitionScale)
            let request = VisionOCRService.makeRequest(settings: settings)
            let supported = Set(try request.supportedRecognitionLanguages())
            let unsupported = settings.languages.filter { !supported.contains($0) }
            guard unsupported.isEmpty else { throw OCRError.unsupportedLanguages(unsupported) }
            if !settings.languages.isEmpty { request.recognitionLanguages = settings.languages }
            guard install(request) else { return }
            let prepared = try OCRImagePreparation.prepare(image, scale: settings.recognitionScale)
            guard !isFinished() else { return }
            try VNImageRequestHandler(cgImage: prepared, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> OCRTextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRTextLine(text: candidate.string, boundingBox: observation.boundingBox)
            }
            finish(.success(OCRTextOrdering.text(from: lines, singleLine: singleLine)))
        } catch let error as OCRError {
            finish(.failure(error))
        } catch {
            finish(.failure(OCRError.recognitionFailed(error.localizedDescription)))
        }
    }
}
