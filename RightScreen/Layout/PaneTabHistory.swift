import CoreGraphics

enum PaneTabHistory {
    /// 最近激活的窗口排在最前；再次激活会去重并移到队首。
    static func recording(_ windowID: CGWindowID, in history: [CGWindowID]) -> [CGWindowID] {
        [windowID] + history.filter { $0 != windowID }
    }

    static func removing(_ windowID: CGWindowID, from history: [CGWindowID]) -> [CGWindowID] {
        history.filter { $0 != windowID }
    }

    /// 当前 Tab 离开窗格后应选中的下标：优先上一工作窗口（MRU），否则落到被移除位置的邻项。
    static func selectedIndex(
        remainingIDs: [CGWindowID],
        history: [CGWindowID],
        removedIndex: Int
    ) -> Int {
        guard !remainingIDs.isEmpty else { return 0 }
        if let id = history.first(where: { remainingIDs.contains($0) }),
           let index = remainingIDs.firstIndex(of: id) {
            return index
        }
        return min(max(0, removedIndex), remainingIDs.count - 1)
    }
}

enum NewWindowPlacement {
    /// 新窗口并入当前正在工作的窗格；焦点格无效时退回窗口最少的格。
    static func paneIndex(lastFocusedPaneIndex: Int, paneWindowCounts: [Int]) -> Int? {
        guard !paneWindowCounts.isEmpty else { return nil }
        if paneWindowCounts.indices.contains(lastFocusedPaneIndex) {
            return lastFocusedPaneIndex
        }
        return paneWindowCounts.indices.min(by: {
            paneWindowCounts[$0] < paneWindowCounts[$1]
        })
    }
}

enum WindowFocusMatch {
    static let maxGeometryDelta: CGFloat = 48

    /// 用 AX frame 对齐窗口时，若多个候选同样接近则视为无法判定，避免同格叠窗总是命中第一项。
    static func bestIndex(deltas: [CGFloat]) -> Int? {
        guard let best = deltas.enumerated().min(by: { $0.element < $1.element }),
              best.element <= maxGeometryDelta
        else {
            return nil
        }

        let tied = deltas.enumerated().filter { candidate in
            candidate.element <= maxGeometryDelta
                && abs(candidate.element - best.element) <= 1
        }
        return tied.count == 1 ? best.offset : nil
    }
}
