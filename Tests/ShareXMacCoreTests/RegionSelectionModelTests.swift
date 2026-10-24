import CoreGraphics
import Testing
@testable import ShareXMacCore

@Suite("Region selection geometry")
struct RegionSelectionModelTests {
    @Test("normalizes a drag whose end point is above and left of its start")
    func normalizesInvertedDrag() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let selection = RegionSelectionModel().selection(start: CGPoint(x: 80, y: 70), end: CGPoint(x: 20, y: 10), in: bounds)

        #expect(selection == CGRect(x: 20, y: 10, width: 60, height: 60))
    }

    @Test("clamps a drag that starts outside the desktop bounds")
    func clampsToBounds() {
        let bounds = CGRect(x: -20, y: -10, width: 100, height: 80)
        let selection = RegionSelectionModel().selection(start: CGPoint(x: -50, y: 30), end: CGPoint(x: 40, y: 100), in: bounds)

        #expect(selection == CGRect(x: -20, y: 30, width: 60, height: 40))
    }

    @Test("returns nil for a zero-area drag or a drag outside the bounds")
    func rejectsZeroAreaAndOutsideDrags() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)

        #expect(RegionSelectionModel().selection(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 20, y: 20), in: bounds) == nil)
        #expect(RegionSelectionModel().selection(start: CGPoint(x: -30, y: -20), end: CGPoint(x: -10, y: -5), in: bounds) == nil)
    }
}
