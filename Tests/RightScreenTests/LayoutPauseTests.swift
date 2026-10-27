import Testing
@testable import RightScreen

struct LayoutPauseTests {
    @Test func firstReasonStartsPause() {
        var pause = LayoutPause()
        let started = pause.begin(.screensAsleep)
        let startedAgain = pause.begin(.screenLocked)
        #expect(started)
        #expect(!startedAgain)
        #expect(pause.isPaused)
    }

    /// 屏幕先亮、锁屏后解：只有最后一个原因解除时才恢复。
    @Test func resumesOnlyWhenAllReasonsEnd() {
        var pause = LayoutPause()
        pause.begin(.screensAsleep)
        pause.begin(.screenLocked)
        let resumedAfterWake = pause.end(.screensAsleep)
        #expect(!resumedAfterWake)
        #expect(pause.isPaused)
        let resumedAfterUnlock = pause.end(.screenLocked)
        #expect(resumedAfterUnlock)
        #expect(!pause.isPaused)
    }

    /// 没开始过的原因收到结束通知（例如启动时就已解锁）不触发恢复。
    @Test func endingUnknownReasonIsIgnored() {
        var pause = LayoutPause()
        let resumed = pause.end(.screenLocked)
        #expect(!resumed)
        #expect(!pause.isPaused)
    }

    @Test func repeatedBeginNeedsSingleEnd() {
        var pause = LayoutPause()
        pause.begin(.systemAsleep)
        pause.begin(.systemAsleep)
        let resumed = pause.end(.systemAsleep)
        #expect(resumed)
    }

    /// 解锁时清掉所有原因：哪怕「亮屏」「会话回到前台」的通知漏发，布局也会恢复。
    @Test func unlockClearsEveryReason() {
        var pause = LayoutPause()
        pause.begin(.screenLocked)
        pause.begin(.sessionInactive)
        let resumed = pause.endAll()
        #expect(resumed)
        #expect(!pause.isPaused)
        let resumedAgain = pause.endAll()
        #expect(!resumedAgain)
    }
}
