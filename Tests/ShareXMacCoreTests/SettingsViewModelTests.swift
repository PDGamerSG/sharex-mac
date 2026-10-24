import Foundation
import Testing
@testable import ShareXMacCore

@Suite("Settings view model")
struct SettingsViewModelTests {
    @Test("changes persist and failed saves preserve the last accepted values")
    @MainActor func updates() throws {
        var saved: AppSettings?
        let model = SettingsViewModel(settings: AppSettings(), save: { saved = $0 })
        #expect(model.update { $0.capture.showCursor = true })
        #expect(saved?.capture.showCursor == true)
        let failed = SettingsViewModel(settings: AppSettings(), save: { _ in throw Failure.write })
        #expect(!failed.update { $0.capture.showCursor = true })
        #expect(!failed.settings.capture.showCursor)
        #expect(failed.errorMessage != nil)
    }
    private enum Failure: Error { case write }
}
