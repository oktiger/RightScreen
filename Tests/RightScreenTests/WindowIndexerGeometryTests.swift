import CoreGraphics
import Testing
@testable import RightScreen

struct WindowIndexerGeometryTests {
    @Test func overlappingFramesCanMatchDespiteChromeStyleInsets() {
        let cgFrame = CGRect(x: 20, y: 40, width: 1200, height: 800)
        let axFrame = CGRect(x: 8, y: 28, width: 1224, height: 824)

        #expect(WindowIndexer.overlapRatio(cgFrame, axFrame) > 0.99)
    }

    @Test func unrelatedFramesDoNotOverlap() {
        let first = CGRect(x: 0, y: 0, width: 500, height: 500)
        let second = CGRect(x: 900, y: 0, width: 500, height: 500)

        #expect(WindowIndexer.overlapRatio(first, second) == 0)
    }
}
