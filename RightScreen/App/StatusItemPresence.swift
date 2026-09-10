import CoreGraphics

/// 判断菜单栏按钮是否被系统停在屏外（macOS 26 关闭「允许在菜单栏中显示」时常见 y≈-22）。
enum StatusItemPresence {
    static func isParkedOffMenuBar(windowFrame: CGRect) -> Bool {
        if windowFrame.width <= 1 || windowFrame.height <= 1 {
            return true
        }
        return windowFrame.maxY <= 0
    }
}
