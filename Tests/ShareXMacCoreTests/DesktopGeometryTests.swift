import CoreGraphics
import Testing
@testable import ShareXMacCore

@Suite("Desktop coordinate conversion")
struct DesktopGeometryTests {
    @Test("converts Quartz top-left coordinates to AppKit bottom-left coordinates")
    func quartzToAppKit() {
        let geometry = DesktopGeometry(quartzBounds: CGRect(x: -500, y: -200, width: 1500, height: 1000), mainDisplayHeight: 800)
        #expect(geometry.appKitBounds == CGRect(x: -500, y: 0, width: 1500, height: 1000))
        #expect(geometry.appKitRect(fromQuartz: CGRect(x: -300, y: -100, width: 200, height: 150)) == CGRect(x: -300, y: 750, width: 200, height: 150))
    }

    @Test("maps a cross-display region to the frozen image pixels")
    func regionPixels() {
        let geometry = DesktopGeometry(quartzBounds: CGRect(x: -500, y: -200, width: 1500, height: 1000), mainDisplayHeight: 800)
        #expect(geometry.pixelRect(forAppKit: CGRect(x: -300, y: 750, width: 200, height: 150), imageWidth: 3000, imageHeight: 2000) == CGRect(x: 400, y: 200, width: 400, height: 300))
    }

    @Test("rejects empty, outside and nonfinite selections")
    func invalidSelections() {
        let model = RegionSelectionModel()
        #expect(model.selection(start: CGPoint(x: CGFloat.nan, y: 0), end: .zero, in: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
        let geometry = DesktopGeometry(quartzBounds: CGRect(x: 0, y: 0, width: 100, height: 100), mainDisplayHeight: 100)
        #expect(geometry.pixelRect(forAppKit: CGRect(x: 200, y: 0, width: 10, height: 10), imageWidth: 200, imageHeight: 200) == nil)
    }
}
