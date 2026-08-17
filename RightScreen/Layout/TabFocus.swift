enum TabFocus {
    /// 快捷键要移动的 Tab：优先系统焦点窗口，其次最近聚焦过的窗格选中 Tab。
    static func moveTarget(
        panes: [PaneState],
        focusedWindow: ManagedWindow?,
        lastFocusedPaneIndex: Int?
    ) -> (paneIndex: Int, tabIndex: Int)? {
        if let focusedWindow {
            for (paneIndex, pane) in panes.enumerated() {
                if let tabIndex = pane.windows.firstIndex(where: {
                    $0.refersToSameAccessibilityWindow(as: focusedWindow)
                }) {
                    return (paneIndex, tabIndex)
                }
            }
        }

        if let lastFocusedPaneIndex,
           panes.indices.contains(lastFocusedPaneIndex) {
            let pane = panes[lastFocusedPaneIndex]
            if pane.windows.indices.contains(pane.selectedIndex) {
                return (lastFocusedPaneIndex, pane.selectedIndex)
            }
        }

        // 进入布局时按窗格顺序 raise，最后一格通常是前台。
        for paneIndex in panes.indices.reversed() {
            let pane = panes[paneIndex]
            if pane.windows.indices.contains(pane.selectedIndex) {
                return (paneIndex, pane.selectedIndex)
            }
        }

        return nil
    }
}
