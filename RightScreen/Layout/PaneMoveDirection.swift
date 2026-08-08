enum PaneMoveDirection: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    var systemSymbolName: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }

    var tooltip: String {
        switch self {
        case .left: "移到左侧"
        case .right: "移到右侧"
        case .up: "移到上方"
        case .down: "移到下方"
        }
    }
}

enum PaneMove {
    /// 当前窗格可向哪些方向移动（顺序：左、右、上、下）。
    static func availableDirections(from paneIndex: Int, kind: LayoutKind) -> [PaneMoveDirection] {
        PaneMoveDirection.allCases.filter { direction in
            destinationPaneIndex(from: paneIndex, direction: direction, kind: kind) != nil
        }
    }

    /// 相邻目标窗格；无合法相邻格时返回 nil。
    static func destinationPaneIndex(
        from paneIndex: Int,
        direction: PaneMoveDirection,
        kind: LayoutKind
    ) -> Int? {
        switch kind {
        case .fullScreen:
            // 单格无邻格，不提供移动。
            return nil

        case .split2:
            switch (paneIndex, direction) {
            case (0, .right): return 1
            case (1, .left): return 0
            default: return nil
            }

        case .topBottom:
            // 0 上，1 下
            switch (paneIndex, direction) {
            case (0, .down): return 1
            case (1, .up): return 0
            default: return nil
            }

        case .focusStack:
            // 0 左主栏，1 右上，2 右下。
            // 左 → 右：落到右上，避免「竖条向右」目标歧义。
            switch (paneIndex, direction) {
            case (0, .right): return 1
            case (1, .left): return 0
            case (1, .down): return 2
            case (2, .left): return 0
            case (2, .up): return 1
            default: return nil
            }

        case .split4:
            // 0 TL, 1 TR, 2 BL, 3 BR
            switch (paneIndex, direction) {
            case (0, .right): return 1
            case (0, .down): return 2
            case (1, .left): return 0
            case (1, .down): return 3
            case (2, .right): return 3
            case (2, .up): return 0
            case (3, .left): return 2
            case (3, .up): return 1
            default: return nil
            }
        }
    }
}
