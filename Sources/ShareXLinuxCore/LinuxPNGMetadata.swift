import Foundation

public enum LinuxPNGMetadata {
    public enum Error: Swift.Error, LocalizedError, Equatable, Sendable {
        case invalidPNG
        case unreadableFile

        public var errorDescription: String? {
            switch self {
            case .invalidPNG: return "The capture did not produce a valid PNG image."
            case .unreadableFile: return "The captured image could not be read."
            }
        }
    }

    public static func read(url: URL) throws -> LinuxImageSize {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Error.unreadableFile }
        let data = handle.readData(ofLength: 24)
        guard data.count >= 24,
              data[0] == 137, data[1] == 80, data[2] == 78, data[3] == 71,
              data[4] == 13, data[5] == 10, data[6] == 26, data[7] == 10,
              data[12] == 73, data[13] == 72, data[14] == 68, data[15] == 82 else {
            throw Error.invalidPNG
        }
        let width = Int(Self.uint32(data, at: 16))
        let height = Int(Self.uint32(data, at: 20))
        guard width > 0, height > 0 else { throw Error.invalidPNG }
        return LinuxImageSize(width: width, height: height)
    }

    private static func uint32(_ data: Data, at index: Int) -> UInt32 {
        UInt32(data[index]) << 24 | UInt32(data[index + 1]) << 16 | UInt32(data[index + 2]) << 8 | UInt32(data[index + 3])
    }
}
