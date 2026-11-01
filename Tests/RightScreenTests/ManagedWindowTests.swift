import ApplicationServices
import CoreGraphics
import Testing
@testable import RightScreen

struct ManagedWindowTests {
    @Test func tabTitleUsesWindowTitle() {
        let window = makeWindow(appName: "OpenBeast", title: " MediaHub ")

        #expect(window.tabTitle == "MediaHub")
    }

    @Test func chromeTabTitleUsesPageTitleOnly() {
        let window = makeWindow(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            title: "OpenAI"
        )

        #expect(window.tabTitle == "OpenAI")
    }

    @Test func tabTitleFallsBackToApplicationNameWhenWindowTitleIsEmpty() {
        let window = makeWindow(appName: " WeChat ", title: "   ")

        #expect(window.tabTitle == "WeChat")
    }

    @Test func accessibilityIdentityIgnoresChangingCGWindowID() {
        let first = makeWindow(
            windowID: 10,
            appName: "WeChat",
            title: "",
            element: AXUIElementCreateApplication(1)
        )
        let second = makeWindow(
            windowID: 20,
            appName: "WeChat",
            title: "",
            element: AXUIElementCreateApplication(1)
        )

        #expect(first.refersToSameAccessibilityWindow(as: second))
    }

    private func makeWindow(
        windowID: CGWindowID = 1,
        bundleIdentifier: String = "com.example.app",
        appName: String,
        title: String,
        element: AXUIElement = AXUIElementCreateApplication(1)
    ) -> ManagedWindow {
        ManagedWindow(
            windowID: windowID,
            ownerPID: 1,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: title,
            frame: .zero,
            element: element
        )
    }
}
