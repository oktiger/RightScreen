import CoreGraphics
import Testing
@testable import RightScreen

struct WindowIndexerGeometryTests {
    @Test func overlappingFramesCanMatchDespiteChromeStyleInsets() {
        let cgFrame = CGRect(x: 20, y: 40, width: 1200, height: 800)
        let axFrame = CGRect(x: 8, y: 28, width: 1224, height: 824)

        #expect(WindowIndexer.overlapRatio(cgFrame, axFrame) > 0.94)
        #expect(WindowIndexer.sizeSimilarity(cgFrame, axFrame) > 0.97)
    }

    @Test func containedPopupDoesNotLookLikeItsParentWindow() {
        let parent = CGRect(x: 50, y: 40, width: 800, height: 760)
        let popup = CGRect(x: 350, y: 420, width: 340, height: 360)

        #expect(WindowIndexer.overlapRatio(parent, popup) < 0.21)
        #expect(WindowIndexer.sizeSimilarity(parent, popup) < 0.48)
    }

    @Test func unrelatedFramesDoNotOverlap() {
        let first = CGRect(x: 0, y: 0, width: 500, height: 500)
        let second = CGRect(x: 900, y: 0, width: 500, height: 500)

        #expect(WindowIndexer.overlapRatio(first, second) == 0)
    }
}
