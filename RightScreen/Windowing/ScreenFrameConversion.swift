import CoreGraphics

enum ScreenFrameConversion {
    /// AX / CGWindowList 与 AppKit 的 Y 轴互转；同一公式可来回使用。
    /// `screenFrame` 必须是菜单栏所在屏（`NSScreen.screens[0]`）的 frame，
    /// 不是布局目标屏。用错 maxY 会在多屏或插拔显示器后把窗口/Tab 条打到错误高度。
    static func flippingY(_ frame: CGRect, relativeTo screenFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
