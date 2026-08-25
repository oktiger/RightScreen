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

    @Test func newWindowsJoinTheFocusedPaneEvenWhenItIsFuller() {
        let paneIndex = NewWindowPlacement.paneIndex(
            lastFocusedPaneIndex: 0,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 0)
    }

    @Test func newWindowsFallBackToTheLeastFullPaneWhenFocusIsUnknown() {
        let paneIndex = NewWindowPlacement.paneIndex(
            lastFocusedPaneIndex: 8,
            paneWindowCounts: [3, 1]
        )

        #expect(paneIndex == 1)
    }

    @Test func geometryMatchRejectsTiedSameFrameCandidates() {
        #expect(WindowFocusMatch.bestIndex(deltas: [0, 0, 0]) == nil)
        #expect(WindowFocusMatch.bestIndex(deltas: [12]) == 0)
        #expect(WindowFocusMatch.bestIndex(deltas: [4, 40]) == 0)
        #expect(WindowFocusMatch.bestIndex(deltas: [80, 90]) == nil)
    }
}
