import CoreGraphics

/// BSP 分割方向。`vertical` = 左右；`horizontal` = 上下（first 为上、second 为下）。
enum BentoSplitOrientation: Equatable, Sendable {
    case vertical
    case horizontal
}

/// 从根到某内部节点的路径。
enum BentoChildSlot: Equatable, Sendable {
    case first
    case second
}

/// Bento BSP 树。叶节点一一对应窗口；内部节点保存分割比例。
indirect enum BentoNode<Value> {
    case leaf(Value)
    case split(
        orientation: BentoSplitOrientation,
        ratio: Double,
        first: BentoNode,
        second: BentoNode
    )
}

struct BentoLeafLayout<Value> {
    let value: Value
    let frame: CGRect
}

struct BentoDividerLayout: Equatable, Sendable {
    /// 指向该分隔对应的 split 节点。
    let path: [BentoChildSlot]
    let orientation: BentoSplitOrientation
    /// 可见间隙矩形（AppKit 坐标）。
    let frame: CGRect
    /// 拖拽命中区（比可见间隙更宽，便于抓取）。
    let hitFrame: CGRect
}

enum BentoEngine {
    static let defaultGap: CGFloat = 8
    static let minimumPaneLength: CGFloat = 120
    /// 可见分隔宽度；命中区为其 3 倍（对齐 BetterStage 文档）。
    static let visibleDividerWidth: CGFloat = 8
    static let hitDividerMultiplier: CGFloat = 3

    /// 按窗口数量构建平衡 BSP：深度偶数左右切，奇数上下切；3 窗时自然得到「左整高 + 右上下」。
    static func buildTree<T>(_ items: [T]) -> BentoNode<T>? {
        guard !items.isEmpty else { return nil }
        return build(items, depth: 0)
    }

    static func layout<T>(
        _ node: BentoNode<T>,
        in frame: CGRect,
        gap: CGFloat = defaultGap
    ) -> (leaves: [BentoLeafLayout<T>], dividers: [BentoDividerLayout]) {
        var leaves: [BentoLeafLayout<T>] = []
        var dividers: [BentoDividerLayout] = []
        layoutNode(node, in: frame, gap: gap, path: [], leaves: &leaves, dividers: &dividers)
        return (leaves, dividers)
    }

    /// 按拖拽位置更新指定 split 的 ratio，并钳制到最小格宽/高。
    static func updatingRatio<T>(
        in node: BentoNode<T>,
        path: [BentoChildSlot],
        location: CGFloat,
        splitFrame: CGRect,
        gap: CGFloat = defaultGap
    ) -> BentoNode<T> {
        guard let orientation = splitOrientation(at: path, in: node) else {
            return node
        }

        let usable: CGFloat
        let offset: CGFloat
        switch orientation {
        case .vertical:
            usable = max(splitFrame.width - gap, 1)
            offset = location - splitFrame.minX
        case .horizontal:
            usable = max(splitFrame.height - gap, 1)
            // first = top。鼠标 y 越大越靠上 → first 越大。
            offset = splitFrame.maxY - location
        }

        let minRatio = Double(minimumPaneLength / usable)
        let maxRatio = Double(1 - minimumPaneLength / usable)
        let rawRatio = Double(offset / usable)
        let clamped: Double
        if minRatio >= maxRatio {
            clamped = 0.5
        } else {
            clamped = min(max(rawRatio, minRatio), maxRatio)
        }
        return replacingRatio(clamped, at: path, in: node)
    }

    /// 返回 path 指向的 split 节点在整棵树布局中的外接 frame。
    static func splitFrame<T>(
        at path: [BentoChildSlot],
        in node: BentoNode<T>,
        rootFrame: CGRect,
        gap: CGFloat = defaultGap
    ) -> CGRect? {
        frameForNode(at: path, in: node, currentFrame: rootFrame, gap: gap)
    }

    static func mapLeaves<A, B>(
        _ node: BentoNode<A>,
        transform: (A) -> B
    ) -> BentoNode<B> {
        switch node {
        case .leaf(let value):
            return .leaf(transform(value))
        case .split(let orientation, let ratio, let first, let second):
            return .split(
                orientation: orientation,
                ratio: ratio,
                first: mapLeaves(first, transform: transform),
                second: mapLeaves(second, transform: transform)
            )
        }
    }

    static func leafValues<T>(_ node: BentoNode<T>) -> [T] {
        switch node {
        case .leaf(let value):
            return [value]
        case .split(_, _, let first, let second):
            return leafValues(first) + leafValues(second)
        }
    }

    // MARK: - Private

    private static func build<T>(_ items: [T], depth: Int) -> BentoNode<T> {
        if items.count == 1 {
            return .leaf(items[0])
        }

        let mid = items.count / 2
        let orientation: BentoSplitOrientation = depth.isMultiple(of: 2) ? .vertical : .horizontal
        return .split(
            orientation: orientation,
            ratio: 0.5,
            first: build(Array(items[..<mid]), depth: depth + 1),
            second: build(Array(items[mid...]), depth: depth + 1)
        )
    }

    private static func layoutNode<T>(
        _ node: BentoNode<T>,
        in frame: CGRect,
        gap: CGFloat,
        path: [BentoChildSlot],
        leaves: inout [BentoLeafLayout<T>],
        dividers: inout [BentoDividerLayout]
    ) {
        switch node {
        case .leaf(let value):
            leaves.append(BentoLeafLayout(value: value, frame: frame))

        case .split(let orientation, let ratio, let first, let second):
            let (firstFrame, secondFrame, dividerFrame) = splitFrames(
                in: frame,
                orientation: orientation,
                ratio: ratio,
                gap: gap
            )
            dividers.append(
                BentoDividerLayout(
                    path: path,
                    orientation: orientation,
                    frame: dividerFrame,
                    hitFrame: expandedHitFrame(dividerFrame, orientation: orientation)
                )
            )
            layoutNode(
                first,
                in: firstFrame,
                gap: gap,
                path: path + [.first],
                leaves: &leaves,
                dividers: &dividers
            )
            layoutNode(
                second,
                in: secondFrame,
                gap: gap,
                path: path + [.second],
                leaves: &leaves,
                dividers: &dividers
            )
        }
    }

    private static func splitFrames(
        in frame: CGRect,
        orientation: BentoSplitOrientation,
        ratio: Double,
        gap: CGFloat
    ) -> (first: CGRect, second: CGRect, divider: CGRect) {
        let clampedRatio = min(max(ratio, 0.05), 0.95)

        switch orientation {
        case .vertical:
            let usable = max(frame.width - gap, 0)
            let firstWidth = floor(usable * clampedRatio)
            let secondWidth = usable - firstWidth
            let first = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: firstWidth,
                height: frame.height
            )
            let second = CGRect(
                x: frame.minX + firstWidth + gap,
                y: frame.minY,
                width: secondWidth,
                height: frame.height
            )
            let divider = CGRect(
                x: frame.minX + firstWidth,
                y: frame.minY,
                width: gap,
                height: frame.height
            )
            return (first, second, divider)

        case .horizontal:
            let usable = max(frame.height - gap, 0)
            let firstHeight = floor(usable * clampedRatio)
            let secondHeight = usable - firstHeight
            // first = top
            let second = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: secondHeight
            )
            let first = CGRect(
                x: frame.minX,
                y: frame.minY + secondHeight + gap,
                width: frame.width,
                height: firstHeight
            )
            let divider = CGRect(
                x: frame.minX,
                y: frame.minY + secondHeight,
                width: frame.width,
                height: gap
            )
            return (first, second, divider)
        }
    }

    private static func expandedHitFrame(
        _ frame: CGRect,
        orientation: BentoSplitOrientation
    ) -> CGRect {
        let extra = max(
            (visibleDividerWidth * hitDividerMultiplier - max(frame.width, frame.height)) / 2,
            4
        )
        switch orientation {
        case .vertical:
            return frame.insetBy(dx: -extra, dy: 0)
        case .horizontal:
            return frame.insetBy(dx: 0, dy: -extra)
        }
    }

    private static func splitOrientation<T>(
        at path: [BentoChildSlot],
        in node: BentoNode<T>
    ) -> BentoSplitOrientation? {
        guard let target = nodeAt(path, in: node) else { return nil }
        if case .split(let orientation, _, _, _) = target {
            return orientation
        }
        return nil
    }

    private static func nodeAt<T>(
        _ path: [BentoChildSlot],
        in node: BentoNode<T>
    ) -> BentoNode<T>? {
        var current = node
        for slot in path {
            guard case .split(_, _, let first, let second) = current else {
                return nil
            }
            current = slot == .first ? first : second
        }
        return current
    }

    private static func replacingRatio<T>(
        _ ratio: Double,
        at path: [BentoChildSlot],
        in node: BentoNode<T>
    ) -> BentoNode<T> {
        if path.isEmpty {
            guard case .split(let orientation, _, let first, let second) = node else {
                return node
            }
            return .split(orientation: orientation, ratio: ratio, first: first, second: second)
        }

        guard case .split(let orientation, let existingRatio, let first, let second) = node else {
            return node
        }

        let slot = path[0]
        let rest = Array(path.dropFirst())
        switch slot {
        case .first:
            return .split(
                orientation: orientation,
                ratio: existingRatio,
                first: replacingRatio(ratio, at: rest, in: first),
                second: second
            )
        case .second:
            return .split(
                orientation: orientation,
                ratio: existingRatio,
                first: first,
                second: replacingRatio(ratio, at: rest, in: second)
            )
        }
    }

    private static func frameForNode<T>(
        at path: [BentoChildSlot],
        in node: BentoNode<T>,
        currentFrame: CGRect,
        gap: CGFloat
    ) -> CGRect? {
        if path.isEmpty {
            return currentFrame
        }

        guard case .split(let orientation, let ratio, let first, let second) = node else {
            return nil
        }

        let (firstFrame, secondFrame, _) = splitFrames(
            in: currentFrame,
            orientation: orientation,
            ratio: ratio,
            gap: gap
        )
        let slot = path[0]
        let rest = Array(path.dropFirst())
        let child = slot == .first ? first : second
        let childFrame = slot == .first ? firstFrame : secondFrame
        return frameForNode(at: rest, in: child, currentFrame: childFrame, gap: gap)
    }
}
