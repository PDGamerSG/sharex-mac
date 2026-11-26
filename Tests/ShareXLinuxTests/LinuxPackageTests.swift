import Foundation
import ShareXLinuxCore
import Testing

struct LinuxPackageTests {
    @Test("Linux core exposes its product name")
    func productName() {
        #expect(ShareXLinuxCore.productName == "ShareX Linux")
    }
}
