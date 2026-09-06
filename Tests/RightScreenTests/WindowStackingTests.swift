import ApplicationServices
import CoreGraphics
import Testing
@testable import RightScreen

struct WindowStackingTests {
    @Test func coveringWindowsSkipSameProcessSiblings() {
        let leftChrome = makeWindow(pid: 10, elementPID: 101)
        let rightChrome = makeWindow(pid: 10, elementPID: 102)
        let rightSafari = makeWindow(pid: 20, elementPID: 201)

        let covering = WindowStacking.coveringWindows(
            keepingFront: leftChrome,
            visibleWindows: [leftChrome, rightChrome, rightSafari]
        )

        #expect(covering.count == 1)
        #expect(covering[0].ownerPID == 20)
    }

    @Test func coveringWindowsKeepEveryOtherAppVisible() {
        let focused = makeWindow(pid: 10, elementPID: 101)
        let finder = makeWindow(pid: 30, elementPID: 301)
        let terminal = makeWindow(pid: 40, elementPID: 401)

        let covering = WindowStacking.coveringWindows(
            keepingFront: focused,
            visibleWindows: [focused, finder, terminal]
        )

        #expect(covering.map(\.ownerPID) == [30, 40])
    }

    @Test func coveringWindowsIgnoreTheFocusedWindowEvenWhenPIDDiffersByIdentityOnly() {
        let focused = makeWindow(pid: 10, elementPID: 101)
        let covering = WindowStacking.coveringWindows(
            keepingFront: focused,
            visibleWindows: [focused]
        )

        #expect(covering.isEmpty)
    }

    private func makeWindow(pid: pid_t, elementPID: pid_t) -> ManagedWindow {
        ManagedWindow(
            windowID: CGWindowID(elementPID),
            ownerPID: pid,
            bundleIdentifier: pid == 10 ? "com.google.Chrome" : "com.example.app",
            appName: "App",
            title: "Window",
            frame: .zero,
            element: AXUIElementCreateApplication(elementPID)
        )
    }
}
