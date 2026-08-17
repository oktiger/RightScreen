import ApplicationServices
import CoreGraphics
import Testing
@testable import RightScreen

struct TabFocusTests {
    @Test func prefersTheFocusedWindowEvenWhenLastPaneDiffers() {
        let left = makeWindow(pid: 1, elementPID: 1)
        let right = makeWindow(pid: 2, elementPID: 2)
        let panes = [
            makePane(windows: [left]),
            makePane(windows: [right])
        ]

        let target = TabFocus.moveTarget(
            panes: panes,
            focusedWindow: left,
            lastFocusedPaneIndex: 1
        )

        #expect(target?.paneIndex == 0)
        #expect(target?.tabIndex == 0)
    }

    @Test func fallsBackToLastFocusedPaneWhenAXFocusIsMissing() {
        let left = makeWindow(pid: 1, elementPID: 1)
        let rightSelected = makeWindow(pid: 2, elementPID: 2)
        let rightOther = makeWindow(pid: 3, elementPID: 3)
        let panes = [
            makePane(windows: [left], selectedIndex: 0),
            makePane(windows: [rightOther, rightSelected], selectedIndex: 1)
        ]

        let target = TabFocus.moveTarget(
            panes: panes,
            focusedWindow: nil,
            lastFocusedPaneIndex: 1
        )

        #expect(target?.paneIndex == 1)
        #expect(target?.tabIndex == 1)
    }

    @Test func lastResortUsesTheTrailingPaneAfterInitialRaiseOrder() {
        let left = makeWindow(pid: 1, elementPID: 1)
        let right = makeWindow(pid: 2, elementPID: 2)
        let panes = [
            makePane(windows: [left]),
            makePane(windows: [right])
        ]

        let target = TabFocus.moveTarget(
            panes: panes,
            focusedWindow: nil,
            lastFocusedPaneIndex: nil
        )

        #expect(target?.paneIndex == 1)
        #expect(target?.tabIndex == 0)
    }

    private func makePane(windows: [ManagedWindow], selectedIndex: Int = 0) -> PaneState {
        PaneState(
            geometry: PaneGeometry(
                paneFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                tabBarFrame: CGRect(x: 0, y: 68, width: 100, height: 32),
                windowFrame: CGRect(x: 0, y: 0, width: 100, height: 68)
            ),
            windows: windows,
            selectedIndex: selectedIndex
        )
    }

    private func makeWindow(pid: pid_t, elementPID: pid_t) -> ManagedWindow {
        ManagedWindow(
            windowID: CGWindowID(pid),
            ownerPID: pid,
            bundleIdentifier: "com.example.app",
            appName: "App",
            title: "Window",
            frame: .zero,
            element: AXUIElementCreateApplication(elementPID)
        )
    }
}
