import CoreGraphics
import Testing
@testable import RightScreen

struct LayoutEngineTests {
    @Test func split2DistributesSixItemsEvenly() {
        let panes = LayoutEngine.assign(Array(0..<6), paneCount: 2)
        #expect(panes == [[0, 1, 2], [3, 4, 5]])
    }

    @Test func remainderGoesToEarlierPanes() {
        let split2 = LayoutEngine.assign(Array(0..<7), paneCount: 2)
        let split4 = LayoutEngine.assign(Array(0..<6), paneCount: 4)

        #expect(split2.map(\.count) == [4, 3])
        #expect(split4.map(\.count) == [2, 2, 1, 1])
        #expect(split4.flatMap { $0 } == Array(0..<6))
    }

    @Test func fewerWindowsKeepTrailingPanesEmpty() {
        let panes = LayoutEngine.assign(["A", "B"], paneCount: 4)
        #expect(panes == [["A"], ["B"], [], []])
    }

    @Test func split2GeometryReservesTabBar() {
        let visibleFrame = CGRect(x: 0, y: 50, width: 1200, height: 800)
        let panes = LayoutEngine.geometries(for: .split2, in: visibleFrame)

        #expect(panes.count == 2)
        #expect(panes[0].paneFrame == CGRect(x: 0, y: 50, width: 600, height: 800))
        #expect(panes[0].tabBarFrame == CGRect(x: 0, y: 818, width: 600, height: 32))
        #expect(panes[0].windowFrame == CGRect(x: 0, y: 50, width: 600, height: 768))
        #expect(panes[1].paneFrame.minX == panes[0].paneFrame.maxX)
    }

    @Test func split4UsesTopLeftTopRightBottomLeftBottomRightOrder() {
        let panes = LayoutEngine.geometries(
            for: .split4,
            in: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )

        #expect(panes.map(\.paneFrame.origin) == [
            CGPoint(x: 10, y: 420),
            CGPoint(x: 510, y: 420),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 510, y: 20)
        ])
    }
}
