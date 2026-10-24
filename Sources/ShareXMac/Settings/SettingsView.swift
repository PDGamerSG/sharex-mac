import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI
import ShareXMacCore

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    let hotkeys: GlobalHotkeyManager
    let folderPath: String
    let databasePath: String
    let chooseFolder: () -> Void
    let openPrivacySettings: () -> Void
    @AppStorage("ShareXMac.startHidden") private var startHidden = false
    @ViewState<[String]> private var languages: [String] = []
    @ViewState<String?> private var languageError: String?
    @ViewState<String?> private var loginError: String?
    @ViewState<SMAppService.Status> private var loginStatus = SMAppService.mainApp.status
    @ViewState<Bool> private var screenPermission = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                captureSettings.tabItem { Label("Capture", systemImage: "camera") }
                storageSettings.tabItem { Label("Storage", systemImage: "folder") }
                ocrSettings.tabItem { Label("OCR", systemImage: "text.viewfinder") }
                HotkeySettingsView(settingsModel: model, manager: hotkeys)
                    .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                generalSettings.tabItem { Label("General", systemImage: "gearshape") }
            }
            if let error = model.errorMessage {
                Divider()
                Label("Settings could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .frame(minWidth: 660, minHeight: 490)
        .task {
            do {
                languages = try await Task.detached { try VisionOCRService.supportedLanguages() }.value
                languageError = nil
            } catch { languageError = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
            screenPermission = CGPreflightScreenCaptureAccess()
        }
    }

    private var captureSettings: some View {
        Form {
            Section {
                Toggle("Include cursor in screenshots", isOn: setting(\.capture.showCursor))
                Stepper(value: setting(\.capture.delaySeconds), in: 0...60, step: 1) {
                    LabeledContent("Capture delay", value: "\(model.settings.capture.delaySeconds.formatted()) seconds")
                }
            } footer: {
                Text("These options apply to all capture modes. The delay runs before the desktop is frozen.")
            }
        }
        .formStyle(.grouped)
    }

    private var storageSettings: some View {
        Form {
            Section("Screenshot folder") {
                Text(folderPath.isEmpty ? "Choose a folder to save screenshots." : folderPath)
                    .textSelection(.enabled)
                    .accessibilityLabel("Screenshot folder: \(folderPath.isEmpty ? "Not selected" : folderPath)")
                if !folderPath.isEmpty {
                    Label(FileManager.default.isWritableFile(atPath: folderPath) ? "Folder is writable" : "Folder is unavailable or not writable", systemImage: FileManager.default.isWritableFile(atPath: folderPath) ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                Button("Choose Folder…", action: chooseFolder)
            }
            Section("Local history database") {
                Text(databasePath).textSelection(.enabled)
                Label(FileManager.default.fileExists(atPath: databasePath) ? "Database is available" : "Database is unavailable", systemImage: FileManager.default.fileExists(atPath: databasePath) ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var ocrSettings: some View {
        Form {
            Section {
                Picker("Recognition scale", selection: setting(\.ocr.recognitionScale)) {
                    ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { scale in Text("\(Int(scale))×").tag(scale) }
                }
                Toggle("Use language correction", isOn: setting(\.ocr.usesLanguageCorrection))
            } footer: {
                Text("A larger scale can help with small text and uses more memory. Text recognition runs on this Mac.")
            }
            Section("Recognition languages") {
                Text("With no languages selected, Vision detects the language automatically.")
                    .foregroundStyle(.secondary)
                if let languageError {
                    Label(languageError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else if languages.isEmpty {
                    ProgressView("Loading supported languages…")
                } else {
                    let unsupported = model.settings.ocr.languages.filter { !languages.contains($0) }
                    if !unsupported.isEmpty {
                        Label("Unsupported saved languages: \(unsupported.joined(separator: ", ")). Use Automatic Detection to clear these choices.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(languages, id: \.self) { language in
                                Toggle(Locale.current.localizedString(forIdentifier: language) ?? language, isOn: Binding(
                                    get: { model.settings.ocr.languages.contains(language) },
                                    set: { selected in
                                        model.update { settings in
                                            settings.ocr.languages.removeAll { $0 == language }
                                            if selected { settings.ocr.languages.append(language) }
                                        }
                                    }
                                ))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .frame(height: 150)
                    Button("Use Automatic Detection") { model.update { $0.ocr.languages = [] } }
                        .disabled(model.settings.ocr.languages.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalSettings: some View {
        Form {
            Section("Launch") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setLaunchAtLogin
                ))
                if loginStatus == .requiresApproval {
                    Text("Allow ShareX in System Settings → General → Login Items to finish enabling launch at login.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                } else if loginStatus == .notFound {
                    Text("Launch at login requires an installed application bundle.")
                        .foregroundStyle(.secondary)
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Toggle("Start hidden", isOn: $startHidden)
                Text("When enabled, ShareX starts in the menu bar without opening a window.")
                    .foregroundStyle(.secondary)
            }
            Section("Screen Recording permission") {
                Label(screenPermission ? "Screen Recording access is allowed" : "Screen Recording access is required for capture", systemImage: screenPermission ? "checkmark.circle" : "exclamationmark.triangle")
                Text("Allow ShareX in Privacy & Security → Screen Recording. macOS may ask you to reopen the application after changing access.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings…", action: openPrivacySettings)
            }
        }
        .formStyle(.grouped)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.update { $0[keyPath: keyPath] = value } })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        loginStatus = SMAppService.mainApp.status
    }
}
