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
        case .split2:
            switch (paneIndex, direction) {
            case (0, .right): 1
            case (1, .left): 0
            default: nil
            }

        case .split4:
            // 0 TL, 1 TR, 2 BL, 3 BR
            switch (paneIndex, direction) {
            case (0, .right): 1
            case (0, .down): 2
            case (1, .left): 0
            case (1, .down): 3
            case (2, .right): 3
            case (2, .up): 0
            case (3, .left): 2
            case (3, .up): 1
            default: nil
            }
        }
    }
}
