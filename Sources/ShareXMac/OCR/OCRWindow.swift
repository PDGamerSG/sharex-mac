import AppKit
import ShareXMacCore
import SwiftUI

@MainActor
final class OCRWindow: NSWindowController, NSWindowDelegate {
    private let model: OCRResultModel
    var onClose: (() -> Void)?

    init(image: CGImage, service: VisionOCRService, settings: OCRSettings) {
        model = OCRResultModel(image: image, service: service, settings: settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Recognized Text"
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OCRResultView(model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        model.startIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        onClose?()
    }
}

@MainActor
private final class OCRResultModel: ObservableObject {
    @Published var text = ""
    @Published var singleLine = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let image: CGImage
    private let service: VisionOCRService
    private let settings: OCRSettings
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var hasStarted = false

    init(image: CGImage, service: VisionOCRService, settings: OCRSettings) {
        self.image = image
        self.service = service
        self.settings = settings
    }

    var displayedText: String {
        singleLine ? OCRTextOrdering.singleLine(text) : text
    }

    var editorText: Binding<String> {
        Binding(get: { self.displayedText }, set: { self.text = $0 })
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        recognize()
    }

    func recognize() {
        task?.cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await service.recognize(image: image, settings: settings)
                guard requestID == id else { return }
                self.text = text
            } catch is CancellationError {
                guard requestID == id else { return }
            } catch {
                guard requestID == id else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedText, forType: .string)
    }
}

@MainActor
private struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Recognizing text…").foregroundStyle(.secondary)
                }
            } else if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            } else if model.text.isEmpty {
                Text("No text was found. Try a region with larger, clearer text.")
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: model.editorText)
                .font(.body)
                .accessibilityLabel("Recognized text")
                .disabled(model.isLoading)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))

            HStack {
                Toggle("Single line", isOn: $model.singleLine).toggleStyle(.checkbox)
                Spacer()
                if !model.isLoading {
                    Button("Try Again", action: model.recognize)
                }
                Button("Copy", action: model.copy)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading || model.displayedText.isEmpty)
            }
        }
        .padding(16)
    }
}
