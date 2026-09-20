/// 判断此刻是否允许对某个受管窗口发起「激活 / 前置」。
///
/// 前置一个窗口必然要把它所属进程切到前台：
/// `SetFrontProcessWithOptions(.frontWindowOnly | .causedByUser)`、
/// `AXFocusedWindow` 写入、`AXRaise`，在系统看来都等于「用户切到了这个 App」。
/// 对已经关掉的窗口做这件事，AppKit / Mac Catalyst 会按 reopen 语义重开一个窗口
/// （相当于点了一下 Dock 图标），表现就是「窗口关掉了，一两秒后又自己弹回来」。
///
/// Mac Catalyst App（例如 Shadowrocket）关窗之后 AXUIElement 仍然可读，
/// 单看 AX 永远认为窗口还在，所以必须再对一次当前 Space 的屏幕窗口名单。
enum WindowActivation {
    /// - Parameters:
    ///   - isAccessibilityElementAlive: AX 元素是否仍然可读。
    ///   - isListedOnScreen: 窗口是否出现在当前 Space 的屏幕窗口名单里。
    ///   - hasOnScreenList: 是否成功读到了屏幕窗口名单；读不到时不下结论，按放行处理。
    static func allowsActivation(
        isAccessibilityElementAlive: Bool,
        isListedOnScreen: Bool,
        hasOnScreenList: Bool
    ) -> Bool {
        guard isAccessibilityElementAlive else { return false }
        guard hasOnScreenList else { return true }
        return isListedOnScreen
    }
}
