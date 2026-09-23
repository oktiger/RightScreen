import CoreGraphics

/// Tab 条的显示档位：宽度不够时依次去掉标题、去掉换格按钮。
enum PaneTabDisplayMode: Equatable {
    /// Icon + 标题 + 换格按钮（选中/悬停时）+ 关闭
    case full
    /// Icon + 换格按钮 + 关闭
    case iconWithMoves
    /// Icon + 关闭（最小形态）
    case iconOnly
}

/// Tab 条排版：Tab 太多时统一缩窄，而不是出现横向滚动条。
/// 最小形态仍放不下时，末尾显示「+N」溢出按钮，点开菜单选其余 Tab。
struct PaneTabStripLayout: Equatable {
    static let maxTabWidth: CGFloat = 154
    static let titleMinWidth: CGFloat = 96
    static let iconAreaWidth: CGFloat = 28
    static let closeButtonWidth: CGFloat = 23
    static let moveButtonWidth: CGFloat = 20
    static let spacing: CGFloat = 4
    static let overflowWidth: CGFloat = 40

    var tabWidth: CGFloat
    var mode: PaneTabDisplayMode
    /// 条上实际显示的 Tab 下标（升序）。
    var visibleIndices: [Int]
    /// 收进溢出菜单的 Tab 下标（升序）。
    var hiddenIndices: [Int]

    var showsOverflow: Bool { !hiddenIndices.isEmpty }

    var stripWidth: CGFloat {
        let count = CGFloat(visibleIndices.count)
        var width = count * tabWidth + max(0, count - 1) * Self.spacing
        if showsOverflow {
            width += Self.spacing + Self.overflowWidth
        }
        return width
    }

    func tabOriginX(atSlot slot: Int) -> CGFloat {
        CGFloat(slot) * (tabWidth + Self.spacing)
    }

    var overflowOriginX: CGFloat {
        tabOriginX(atSlot: visibleIndices.count)
    }

    static func minimumWidth(for mode: PaneTabDisplayMode, moveCount: Int) -> CGFloat {
        switch mode {
        case .full:
            return titleMinWidth
        case .iconWithMoves:
            return iconAreaWidth + closeButtonWidth + CGFloat(moveCount) * moveButtonWidth
        case .iconOnly:
            return iconAreaWidth + closeButtonWidth
        }
    }

    static func make(
        tabCount: Int,
        selectedIndex: Int,
        moveCount: Int,
        availableWidth: CGFloat
    ) -> PaneTabStripLayout {
        guard tabCount > 0 else {
            return PaneTabStripLayout(tabWidth: maxTabWidth, mode: .full, visibleIndices: [], hiddenIndices: [])
        }

        let count = CGFloat(tabCount)
        let fitted = floor((availableWidth - spacing * (count - 1)) / count)
        let width = min(maxTabWidth, fitted)
        let all = Array(0..<tabCount)

        if width >= minimumWidth(for: .full, moveCount: moveCount) {
            return PaneTabStripLayout(tabWidth: width, mode: .full, visibleIndices: all, hiddenIndices: [])
        }
        if moveCount > 0, width >= minimumWidth(for: .iconWithMoves, moveCount: moveCount) {
            return PaneTabStripLayout(tabWidth: width, mode: .iconWithMoves, visibleIndices: all, hiddenIndices: [])
        }
        let iconOnlyWidth = minimumWidth(for: .iconOnly, moveCount: moveCount)
        if width >= iconOnlyWidth {
            return PaneTabStripLayout(tabWidth: width, mode: .iconOnly, visibleIndices: all, hiddenIndices: [])
        }

        // 最小形态也放不下：留出溢出按钮，其余 Tab 进菜单。当前 Tab 始终留在条上。
        let slots = max(1, Int(floor((availableWidth - overflowWidth) / (iconOnlyWidth + spacing))))
        var visible = Array(0..<min(slots, tabCount))
        if all.indices.contains(selectedIndex), !visible.contains(selectedIndex) {
            visible[visible.count - 1] = selectedIndex
        }
        let hidden = all.filter { !visible.contains($0) }
        return PaneTabStripLayout(
            tabWidth: iconOnlyWidth,
            mode: .iconOnly,
            visibleIndices: visible,
            hiddenIndices: hidden
        )
    }
}
