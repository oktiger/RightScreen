import AppKit

/// 状态栏菜单用的矢量布局预览：深色底板 + 蓝色圆角窗格，对齐 BetterStage 卡片示意。
enum LayoutKindIcon {
    private static let canvasSize = CGSize(width: 22, height: 16)
    private static let outerInset: CGFloat = 0.5
    private static let paneGap: CGFloat = 1.5
    private static let outerCorner: CGFloat = 3
    private static let paneCorner: CGFloat = 2

    private static let plateColor = NSColor(calibratedWhite: 0.22, alpha: 1)
    private static let paneColor = NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.98, alpha: 1)

    static func image(for kind: LayoutKind) -> NSImage {
        let size = canvasSize
        let image = NSImage(size: size, flipped: false) { rect in
            draw(kind: kind, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(kind: LayoutKind, in rect: CGRect) {
        let plate = rect.insetBy(dx: outerInset, dy: outerInset)
        drawRoundedRect(plate, radius: outerCorner, color: plateColor)

        let content = plate.insetBy(dx: paneGap, dy: paneGap)
        let panes = paneRects(for: kind, in: content, gap: paneGap)
        for pane in panes {
            drawRoundedRect(pane, radius: paneCorner, color: paneColor)
        }
    }

    /// 与 LayoutEngine 窗格顺序一致的示意矩形（图标坐标系 y 向上）。
    private static func paneRects(for kind: LayoutKind, in frame: CGRect, gap: CGFloat) -> [CGRect] {
        let midX = frame.minX + floor((frame.width - gap) / 2)
        let rightX = midX + gap
        let leftWidth = midX - frame.minX
        let rightWidth = frame.maxX - rightX
        let midY = frame.minY + floor((frame.height - gap) / 2)
        let topY = midY + gap
        let bottomHeight = midY - frame.minY
        let topHeight = frame.maxY - topY

        switch kind {
        case .fullScreen:
            return [frame]

        case .split2:
            return [
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height),
                CGRect(x: rightX, y: frame.minY, width: rightWidth, height: frame.height)
            ]

        case .topBottom:
            return [
                CGRect(x: frame.minX, y: topY, width: frame.width, height: topHeight),
                CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottomHeight)
            ]

        case .focusStack:
            return [
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height),
                CGRect(x: rightX, y: topY, width: rightWidth, height: topHeight),
                CGRect(x: rightX, y: frame.minY, width: rightWidth, height: bottomHeight)
            ]

        case .split4:
            return [
                CGRect(x: frame.minX, y: topY, width: leftWidth, height: topHeight),
                CGRect(x: rightX, y: topY, width: rightWidth, height: topHeight),
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: bottomHeight),
                CGRect(x: rightX, y: frame.minY, width: rightWidth, height: bottomHeight)
            ]
        }
    }

    private static func drawRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()
    }
}
