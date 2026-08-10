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

    @Test func focusStackAssignsThreePanesWithRemainderOnLeft() {
        let panes = LayoutEngine.assign(Array(0..<5), paneCount: LayoutKind.focusStack.paneCount)
        #expect(panes.map(\.count) == [2, 2, 1])
        #expect(panes.flatMap { $0 } == Array(0..<5))
    }

    @Test func fullScreenGeometryIsSinglePane() {
        let visibleFrame = CGRect(x: 0, y: 50, width: 1200, height: 800)
        let panes = LayoutEngine.geometries(for: .fullScreen, in: visibleFrame)

        #expect(panes.count == 1)
        #expect(panes[0].paneFrame == visibleFrame)
        #expect(panes[0].tabBarFrame.height == LayoutEngine.tabBarHeight)
        #expect(panes[0].windowFrame.height == visibleFrame.height - LayoutEngine.tabBarHeight)
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

    @Test func topBottomGeometryStacksVertically() {
        let panes = LayoutEngine.geometries(
            for: .topBottom,
            in: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )

        #expect(panes.count == 2)
        #expect(panes[0].paneFrame == CGRect(x: 10, y: 420, width: 1000, height: 400))
        #expect(panes[1].paneFrame == CGRect(x: 10, y: 20, width: 1000, height: 400))
    }

    @Test func focusStackGeometryIsLeftPlusRightStack() {
        let panes = LayoutEngine.geometries(
            for: .focusStack,
            in: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )

        #expect(panes.map(\.paneFrame) == [
            CGRect(x: 10, y: 20, width: 500, height: 800),
            CGRect(x: 510, y: 420, width: 500, height: 400),
            CGRect(x: 510, y: 20, width: 500, height: 400)
        ])
    }

    @Test func stackFocusGeometryIsLeftStackPlusRightMain() {
        let panes = LayoutEngine.geometries(
            for: .stackFocus,
            in: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )

        #expect(panes.map(\.paneFrame) == [
            CGRect(x: 10, y: 420, width: 500, height: 400),
            CGRect(x: 10, y: 20, width: 500, height: 400),
            CGRect(x: 510, y: 20, width: 500, height: 800)
        ])
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
