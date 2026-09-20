import Testing
@testable import RightScreen

struct WindowActivationTests {
    @Test func deadAccessibilityElementIsNeverActivated() {
        #expect(
            WindowActivation.allowsActivation(
                isAccessibilityElementAlive: false,
                isListedOnScreen: false,
                hasOnScreenList: true
            ) == false
        )
    }

    @Test func windowListedOnScreenIsActivated() {
        #expect(
            WindowActivation.allowsActivation(
                isAccessibilityElementAlive: true,
                isListedOnScreen: true,
                hasOnScreenList: true
            )
        )
    }

    /// Mac Catalyst App（Shadowrocket）关窗后 AX 元素仍然可读。
    /// 对这个「僵尸元素」发起前置会被系统当成用户激活该 App，窗口会被重新开出来。
    @Test func lingeringElementMissingFromTheOnScreenListIsNotActivated() {
        #expect(
            WindowActivation.allowsActivation(
                isAccessibilityElementAlive: true,
                isListedOnScreen: false,
                hasOnScreenList: true
            ) == false
        )
    }

    /// 读不到屏幕窗口名单时不下结论，否则正常布局会整体卡住。
    @Test func missingOnScreenListFallsBackToActivating() {
        #expect(
            WindowActivation.allowsActivation(
                isAccessibilityElementAlive: true,
                isListedOnScreen: false,
                hasOnScreenList: false
            )
        )
    }
}
