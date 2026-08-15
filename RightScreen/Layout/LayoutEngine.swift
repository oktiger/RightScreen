import CoreGraphics

enum LayoutEngine {
    static let tabBarHeight: CGFloat = 32

    /// 连续均分，余数依次补给前面的窗格，因此 6 个窗口在 Split 2 中为 3/3。
    static func assign<T>(_ items: [T], paneCount: Int) -> [[T]] {
        guard paneCount > 0 else { return [] }

        let baseCount = items.count / paneCount
        let remainder = items.count % paneCount
        var cursor = 0

        return (0..<paneCount).map { paneIndex in
            let count = baseCount + (paneIndex < remainder ? 1 : 0)
            let end = cursor + count
            defer { cursor = end }
            return Array(items[cursor..<end])
        }
    }

    static func geometries(
        for kind: LayoutKind,
        in visibleFrame: CGRect,
        tabBarHeight: CGFloat = tabBarHeight
    ) -> [PaneGeometry] {
        paneFrames(for: kind, in: visibleFrame).map { paneFrame in
            let clampedTabHeight = min(max(0, tabBarHeight), paneFrame.height)
            let tabFrame = CGRect(
                x: paneFrame.minX,
                y: paneFrame.maxY - clampedTabHeight,
                width: paneFrame.width,
                height: clampedTabHeight
            )
            let windowFrame = CGRect(
                x: paneFrame.minX,
                y: paneFrame.minY,
                width: paneFrame.width,
                height: paneFrame.height - clampedTabHeight
            )
            return PaneGeometry(
                paneFrame: paneFrame,
                tabBarFrame: tabFrame,
                windowFrame: windowFrame
            )
        }
    }

    private static func paneFrames(for kind: LayoutKind, in frame: CGRect) -> [CGRect] {
        let leftWidth = floor(frame.width / 2)
        let rightWidth = frame.width - leftWidth
        let bottomHeight = floor(frame.height / 2)
        let topHeight = frame.height - bottomHeight

        switch kind {
        case .fullScreen:
            return [frame]

        case .split2:
            return [
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height),
                CGRect(x: frame.minX + leftWidth, y: frame.minY, width: rightWidth, height: frame.height)
            ]

        case .split3:
            // 连续均分宽度，余数像素给最右格，与 split2 把余数给右侧一致。
            let columnWidth = floor(frame.width / 3)
            let middleWidth = columnWidth
            let trailingWidth = frame.width - columnWidth - middleWidth
            return [
                CGRect(x: frame.minX, y: frame.minY, width: columnWidth, height: frame.height),
                CGRect(
                    x: frame.minX + columnWidth,
                    y: frame.minY,
                    width: middleWidth,
                    height: frame.height
                ),
                CGRect(
                    x: frame.minX + columnWidth + middleWidth,
                    y: frame.minY,
                    width: trailingWidth,
                    height: frame.height
                )
            ]

        case .topBottom:
            return [
                CGRect(
                    x: frame.minX,
                    y: frame.minY + bottomHeight,
                    width: frame.width,
                    height: topHeight
                ),
                CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottomHeight)
            ]

        case .focusStack:
            // 0 左主栏，1 右上，2 右下。从左格向右移动时落到右上（见 PaneMove）。
            return [
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: frame.height),
                CGRect(
                    x: frame.minX + leftWidth,
                    y: frame.minY + bottomHeight,
                    width: rightWidth,
                    height: topHeight
                ),
                CGRect(
                    x: frame.minX + leftWidth,
                    y: frame.minY,
                    width: rightWidth,
                    height: bottomHeight
                )
            ]

        case .stackFocus:
            // 0 左上，1 左下，2 右主栏。从右格向左移动时落到左上（见 PaneMove）。
            return [
                CGRect(
                    x: frame.minX,
                    y: frame.minY + bottomHeight,
                    width: leftWidth,
                    height: topHeight
                ),
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: bottomHeight),
                CGRect(
                    x: frame.minX + leftWidth,
                    y: frame.minY,
                    width: rightWidth,
                    height: frame.height
                )
            ]

        case .split4:
            return [
                CGRect(
                    x: frame.minX,
                    y: frame.minY + bottomHeight,
                    width: leftWidth,
                    height: topHeight
                ),
                CGRect(
                    x: frame.minX + leftWidth,
                    y: frame.minY + bottomHeight,
                    width: rightWidth,
                    height: topHeight
                ),
                CGRect(x: frame.minX, y: frame.minY, width: leftWidth, height: bottomHeight),
                CGRect(
                    x: frame.minX + leftWidth,
                    y: frame.minY,
                    width: rightWidth,
                    height: bottomHeight
                )
            ]
        }
    }
}
