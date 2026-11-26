import Foundation
import ShareXLinuxCore
import Testing

struct LinuxPNGMetadataTests {
    @Test("PNG metadata reads dimensions from the IHDR header")
    func dimensions() throws {
        let directory = try LinuxTestTemporaryDirectory()
        defer { directory.remove() }
        let header = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
                           0, 0, 3, 32, 0, 0, 2, 88, 8, 6, 0, 0, 0])
        let url = directory.url.appendingPathComponent("image.png")
        try header.write(to: url)
        #expect(try LinuxPNGMetadata.read(url: url) == LinuxImageSize(width: 800, height: 600))
    }
}
