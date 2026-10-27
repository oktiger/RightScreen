import Foundation

/// 息屏、锁屏、系统睡眠、切换用户期间暂停布局维护。
///
/// 这些时段里显示器会被系统临时拿掉或换成占位屏，屏幕窗口名单也可能是空的或残缺的。
/// 照常巡检的话，窗口会被当成已关闭移出格位、醒来后再按落点重新接管，
/// 用户看到的就是「解锁后整个桌面被重新排了一遍」。
struct LayoutPause {
    enum Reason: Hashable, CaseIterable {
        case screensAsleep
        case screenLocked
        case systemAsleep
        case sessionInactive
    }

    private(set) var reasons = Set<Reason>()

    var isPaused: Bool {
        !reasons.isEmpty
    }

    /// 返回 true 表示这次调用让布局从运行进入暂停。
    @discardableResult
    mutating func begin(_ reason: Reason) -> Bool {
        let wasPaused = isPaused
        reasons.insert(reason)
        return !wasPaused
    }

    /// 返回 true 表示所有暂停原因都已解除，布局应当恢复。
    @discardableResult
    mutating func end(_ reason: Reason) -> Bool {
        guard reasons.remove(reason) != nil else { return false }
        return !isPaused
    }
}
