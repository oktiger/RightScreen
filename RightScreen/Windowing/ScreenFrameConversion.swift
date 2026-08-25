import CoreGraphics

enum ScreenFrameConversion {
    /// AX / CGWindowList 与 AppKit 的 Y 轴互转；同一公式可来回使用。
    static func flippingY(_ frame: CGRect, relativeTo screenFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
