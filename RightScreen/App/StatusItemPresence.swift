import CoreGraphics

/// 判断菜单栏按钮是否没拿到真正的菜单栏槽位。
///
/// 系统拒绝分配槽位时，AppKit 会把按钮窗口停在兜底位置，实测见过两种形态：
/// - 停到屏外（关闭「允许在菜单栏中显示」时常见 y≈-22）；
/// - 停在屏幕右上角，且高度只有 `NSStatusBar.thickness`（22）而非菜单栏实际高度（如 30），
///   于是被时钟/控制中心盖住，看起来就是「图标不见了」。
enum StatusItemPresence {
    /// - Parameters:
    ///   - windowFrame: 按钮窗口的 frame（Cocoa 坐标，y 向上）。
    ///   - screenFrame: 按钮所在屏幕的 frame；传 nil 时只做屏外判断。
    ///   - menuBarHeight: 该屏菜单栏高度（`screen.frame.maxY - screen.visibleFrame.maxY`）；<= 0 时跳过高度判断。
    static func isParkedOffMenuBar(
        windowFrame: CGRect,
        screenFrame: CGRect? = nil,
        menuBarHeight: CGFloat = 0
    ) -> Bool {
        if windowFrame.width <= 1 || windowFrame.height <= 1 {
            return true
        }
        if windowFrame.maxY <= 0 {
            return true
        }
        guard let screenFrame else {
            return false
        }
        // 兜底位置紧贴屏幕右缘：x == screenFrame.maxX - width。
        let pinnedToRightEdge = abs(windowFrame.maxX - screenFrame.maxX) < 1
        // 真正的槽位与菜单栏等高；兜底窗口只有 status bar thickness，明显偏矮。
        let shorterThanMenuBar = menuBarHeight > 0 && windowFrame.height < menuBarHeight - 1
        return pinnedToRightEdge && shorterThanMenuBar
    }
}
