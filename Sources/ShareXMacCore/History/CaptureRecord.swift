import Foundation

public struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let mode: CaptureMode
    public let path: String
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let applicationName: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), mode: CaptureMode, path: String, width: Int, height: Int, windowTitle: String? = nil, applicationName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.path = path
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.applicationName = applicationName
    }
}
