import CoreGraphics
import Testing
@testable import RightScreen

struct PaneTabHistoryTests {
    @Test func recordingMovesTheWindowToTheFrontAndDedupes() {
        let history = PaneTabHistory.recording(3, in: [1, 2, 3])

        #expect(history == [3, 1, 2])
    }

    @Test func movingTheNewestWindowRestoresThePreviousWorkingWindow() {
        // 左格 Tab 1/2/3，正在用 3；新窗口 4 激活后再被移走，应回到 3 而不是 1。
        let remaining: [CGWindowID] = [1, 2, 3]
        let history: [CGWindowID] = [4, 3, 1]
        let index = PaneTabHistory.selectedIndex(
            remainingIDs: remaining,
            history: history,
            removedIndex: 3
        )

        #expect(index == 2)
        #expect(remaining[index] == 3)
    }

    @Test func emptyHistoryFallsBackToTheNeighborSlot() {
        let remaining: [CGWindowID] = [1, 2, 3]
        let index = PaneTabHistory.selectedIndex(
            remainingIDs: remaining,
            history: [],
            removedIndex: 1
        )

        #expect(index == 1)
    }

    @Test func removingTheTrailingTabWithoutHistorySelectsTheNewLastTab() {
        let remaining: [CGWindowID] = [1, 2, 3]
        let index = PaneTabHistory.selectedIndex(
            remainingIDs: remaining,
            history: [],
            removedIndex: 3
        )

        #expect(index == 2)
    }

    @Test func newWindowsJoinThePaneUnderTheirCenterEvenWhenFocusDiffers() {
        let panes = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1200, height: 800)
        )
        let droppedOnRight = CGRect(x: 720, y: 200, width: 240, height: 180)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: droppedOnRight,
            paneFrames: panes.map(\.paneFrame),
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 1)
    }

    @Test func dropOnTheLeftKeepsTheFocusedPaneEvenWhenItIsFuller() {
        let panes = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1200, height: 800)
        )
        let droppedOnLeft = CGRect(x: 80, y: 200, width: 240, height: 180)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: droppedOnLeft,
            paneFrames: panes.map(\.paneFrame),
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 0)
    }

    @Test func newWindowsJoinTheFocusedPaneWhenTheDropIsAmbiguous() {
        let panes = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1200, height: 800)
        )
        let offscreen = CGRect(x: 2000, y: 200, width: 120, height: 120)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: offscreen,
            paneFrames: panes.map(\.paneFrame),
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 0)
    }

    @Test func newWindowsFallBackToTheLeastFullPaneWhenFocusIsUnknown() {
        let panes = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1200, height: 800)
        )
        let offscreen = CGRect(x: 2000, y: 200, width: 120, height: 120)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: offscreen,
            paneFrames: panes.map(\.paneFrame),
            lastFocusedPaneIndex: 8,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 1)
    }

    @Test func overlappingWindowUsesThePaneWithTheUniqueLargestIntersection() {
        let panes = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1200, height: 800)
        )
        // 中心已出右边界，但仍与右格相交、与左格不相交。
        let hangingOffRight = CGRect(x: 1100, y: 200, width: 400, height: 200)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: hangingOffRight,
            paneFrames: panes.map(\.paneFrame),
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [1, 1]
        )

        #expect(paneIndex == 1)
    }

    @Test func equalOverlapFallsBackToTheFocusedPane() {
        let paneFrames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100)
        ]
        // 中心落在两格共用的 max 边上（不含），左右相交面积相同。
        let straddlingAbove = CGRect(x: 50, y: 80, width: 100, height: 40)

        let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: straddlingAbove,
            paneFrames: paneFrames,
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [2, 2]
        )

        #expect(paneIndex == 0)
    }

    @Test func screenFrameConversionFlipsYAndRoundTrips() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let appKit = CGRect(x: 100, y: 200, width: 400, height: 300)

        let accessibility = ScreenFrameConversion.flippingY(appKit, relativeTo: screen)
        #expect(accessibility.origin == CGPoint(x: 100, y: 400))
        #expect(accessibility.size == appKit.size)

        let roundTrip = ScreenFrameConversion.flippingY(accessibility, relativeTo: screen)
        #expect(roundTrip == appKit)
    }

    @Test func geometryMatchRejectsTiedSameFrameCandidates() {
        #expect(WindowFocusMatch.bestIndex(deltas: [0, 0, 0]) == nil)
        #expect(WindowFocusMatch.bestIndex(deltas: [12]) == 0)
        #expect(WindowFocusMatch.bestIndex(deltas: [4, 40]) == 0)
        #expect(WindowFocusMatch.bestIndex(deltas: [80, 90]) == nil)
    }

    @Test func paneFrameFitAcceptsChromeStyleInsets() {
        let expected = CGRect(x: 20, y: 40, width: 600, height: 768)
        let chromeInset = CGRect(x: 8, y: 28, width: 624, height: 792)

        #expect(PaneFrameFit.matches(chromeInset, expected: expected))
    }

    @Test func paneFrameFitRejectsTheDetachedOriginalSize() {
        let expected = CGRect(x: 600, y: 50, width: 600, height: 768)
        let dropped = CGRect(x: 720, y: 200, width: 240, height: 180)

        #expect(!PaneFrameFit.matches(dropped, expected: expected))
    }
}
