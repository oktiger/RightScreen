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

    /// 菜单栏按钮图标：模板绘制，不依赖 SF Symbol（部分系统上 `systemSymbolName` 会得到 nil）。
    static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.5, dy: 3)
            let path = NSBezierPath(roundedRect: inset, xRadius: 2.5, yRadius: 2.5)
            path.lineWidth = 1.4
            NSColor.black.setStroke()
            path.stroke()

            let gap: CGFloat = 1.4
            let midX = inset.midX
            let divider = NSBezierPath()
            divider.lineWidth = 1.4
            divider.move(to: NSPoint(x: midX, y: inset.minY + gap))
            divider.line(to: NSPoint(x: midX, y: inset.maxY - gap))
            divider.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func image(for kind: LayoutKind) -> NSImage {
        let size = canvasSize
        let image = NSImage(size: size, flipped: false) { rect in
            draw(kind: kind, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Grid Mode 菜单图标：不规则四格示意（交错横线）。
    static func bentoImage() -> NSImage {
        let size = canvasSize
        let image = NSImage(size: size, flipped: false) { rect in
            let plate = rect.insetBy(dx: outerInset, dy: outerInset)
            drawRoundedRect(plate, radius: outerCorner, color: plateColor)

            let content = plate.insetBy(dx: paneGap, dy: paneGap)
            let midX = content.minX + floor((content.width - paneGap) / 2)
            let rightX = midX + paneGap
            let leftWidth = midX - content.minX
            let rightWidth = content.maxX - rightX
            let leftSplit = content.minY + floor(content.height * 0.38)
            let rightSplit = content.minY + floor(content.height * 0.62)

            let panes = [
                CGRect(x: content.minX, y: leftSplit + paneGap, width: leftWidth, height: content.maxY - leftSplit - paneGap),
                CGRect(x: content.minX, y: content.minY, width: leftWidth, height: leftSplit - content.minY),
                CGRect(x: rightX, y: rightSplit + paneGap, width: rightWidth, height: content.maxY - rightSplit - paneGap),
                CGRect(x: rightX, y: content.minY, width: rightWidth, height: rightSplit - content.minY)
            ]
            for pane in panes {
                drawRoundedRect(pane, radius: paneCorner, color: paneColor)
            }
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

        case .split3:
            let columnWidth = floor((frame.width - gap * 2) / 3)
            let middleX = frame.minX + columnWidth + gap
            let trailingX = middleX + columnWidth + gap
            let trailingWidth = frame.maxX - trailingX
            return [
                CGRect(x: frame.minX, y: frame.minY, width: columnWidth, height: frame.height),
                CGRect(x: middleX, y: frame.minY, width: columnWidth, height: frame.height),
                CGRect(x: trailingX, y: frame.minY, width: trailingWidth, height: frame.height)
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

        case .stackFocus:
            return [
                CGRect(x: frame.minX, y: topY, width: leftWidth, height: topHeight),
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: bottomHeight),
                CGRect(x: rightX, y: frame.minY, width: rightWidth, height: frame.height)
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
