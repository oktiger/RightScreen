/// 判断一个窗口是不是真的已经被关掉。
///
/// AX 一个信号不够用：Mac Catalyst App（例如 Shadowrocket）关掉窗口之后，
/// 它的 AXUIElement 仍然可读，窗口却已经从屏幕上消失。
/// CG 的当前 Space 窗口名单能补上这一点，但最小化的窗口同样不在名单里，
/// 所以要把这两种情况分开。
enum WindowClosure {
    static func isClosed(
        accessibilityElementAlive: Bool,
        isListedOnScreen: Bool,
        isMinimized: Bool
    ) -> Bool {
        guard accessibilityElementAlive else { return true }
        guard !isListedOnScreen else { return false }
        return !isMinimized
    }
}
