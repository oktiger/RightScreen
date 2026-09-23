import CoreGraphics
import Testing
@testable import RightScreen

struct PaneReconciliationTests {
    private let geometries = LayoutEngine.geometries(
        for: .split2,
        in: CGRect(x: 0, y: 0, width: 1200, height: 800)
    )

    private func reconcile(
        _ panes: [[CGWindowID]],
        frames: [CGWindowID: CGRect]
    ) -> PaneReconciliation.Result {
        PaneReconciliation.reconcile(
            panes: panes,
            currentFrames: frames,
            paneFrames: geometries.map(\.paneFrame),
            windowFrames: geometries.map(\.windowFrame)
        )
    }

    @Test func fittedWindowsKeepPaneAndOrder() {
        let left = geometries[0].windowFrame
        let right = geometries[1].windowFrame
        var frames: [CGWindowID: CGRect] = [1: left]
        for id in CGWindowID(2)...7 {
            frames[id] = right
        }

        let result = reconcile([[1], [7, 3, 2, 6, 5, 4]], frames: frames)

        #expect(result.panes == [[1], [7, 3, 2, 6, 5, 4]])
        #expect(result.movedWindowIDs.isEmpty)
    }

    @Test func shrunkWindowStaysInItsOwnPane() {
        let right = geometries[1].windowFrame
        let shrunk = CGRect(x: 700, y: 200, width: 300, height: 200)

        let result = reconcile(
            [[1], [2, 3, 4]],
            frames: [1: geometries[0].windowFrame, 2: right, 3: shrunk, 4: right]
        )

        #expect(result.panes == [[1], [2, 3, 4]])
        #expect(result.movedWindowIDs.isEmpty)
    }

    @Test func escapedWindowJoinsThePaneUnderItsCenterAtTheEnd() {
        let left = geometries[0].windowFrame
        let right = geometries[1].windowFrame
        let draggedLeft = CGRect(x: 100, y: 100, width: 400, height: 300)

        let result = reconcile(
            [[1, 2], [3, 4, 5]],
            frames: [1: left, 2: left, 3: right, 4: draggedLeft, 5: right]
        )

        #expect(result.panes == [[1, 2, 4], [3, 5]])
        #expect(result.movedWindowIDs == [4: 0])
    }

    @Test func unreadableOrOffScreenWindowsStayPut() {
        let offScreen = CGRect(x: 5000, y: 5000, width: 400, height: 300)

        let result = reconcile([[1], [2, 3]], frames: [1: offScreen, 3: geometries[1].windowFrame])

        #expect(result.panes == [[1], [2, 3]])
        #expect(result.movedWindowIDs.isEmpty)
    }
}
