import Combine
import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var errorMessage: String?
    private let save: (AppSettings) throws -> Void

    public init(settings: AppSettings, save: @escaping (AppSettings) throws -> Void) {
        self.settings = settings
        self.save = save
    }

    @discardableResult
    public func update(_ mutation: (inout AppSettings) -> Void) -> Bool {
        var candidate = settings
        mutation(&candidate)
        candidate.capture.delaySeconds = candidate.capture.normalizedDelaySeconds
        do {
            try save(candidate)
            settings = candidate
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
