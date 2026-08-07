import ApplicationServices
import CoreGraphics
import Testing
@testable import RightScreen

struct ManagedWindowTests {
    @Test func tabTitleUsesApplicationNameInsteadOfWindowTitle() {
        let window = makeWindow(appName: "Antigravity", title: "RightScreen")

        #expect(window.tabTitle == "Antigravity")
    }

    @Test func chromeTabTitleIncludesApplicationAndPageTitle() {
        let window = makeWindow(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            title: "OpenAI"
        )

        #expect(window.tabTitle == "Google Chrome：OpenAI")
    }

    @Test func chromeWithoutPageTitleUsesApplicationNameOnly() {
        let window = makeWindow(
            bundleIdentifier: "com.google.Chrome.canary",
            appName: "Google Chrome Canary",
            title: "   "
        )

        #expect(window.tabTitle == "Google Chrome Canary")
    }

    @Test func tabTitleFallsBackToWindowTitleWhenApplicationNameIsEmpty() {
        let window = makeWindow(appName: "   ", title: " RightScreen ")

        #expect(window.tabTitle == "RightScreen")
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
