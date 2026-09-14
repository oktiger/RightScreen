import Testing
@testable import RightScreen

struct WindowClosureTests {
    @Test func deadAccessibilityElementMeansClosed() {
        #expect(
            WindowClosure.isClosed(
                accessibilityElementAlive: false,
                isListedOnScreen: false,
                isMinimized: false
            )
        )
    }

    @Test func windowStillListedOnScreenIsNotClosed() {
        #expect(
            WindowClosure.isClosed(
                accessibilityElementAlive: true,
                isListedOnScreen: true,
                isMinimized: false
            ) == false
        )
    }

    /// Mac Catalyst App 关掉窗口之后 AXUIElement 依旧可读，
    /// 只有当前 Space 的窗口名单才能看出窗口已经没了。
    @Test func lingeringElementMissingFromTheOnScreenListIsClosed() {
        #expect(
            WindowClosure.isClosed(
                accessibilityElementAlive: true,
                isListedOnScreen: false,
                isMinimized: false
            )
        )
    }

    @Test func minimizedWindowIsNotClosedEvenThoughItLeavesTheOnScreenList() {
        #expect(
            WindowClosure.isClosed(
                accessibilityElementAlive: true,
                isListedOnScreen: false,
                isMinimized: true
            ) == false
        )
    }
}
