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
    /// 新窗口按落点并入：中心点命中的格优先；中心脱格时取相交面积唯一最大的格；再退回焦点格，焦点无效则窗口最少的格。
    /// `windowFrame` / `paneFrames` 须同为 AppKit 坐标（与 `PaneGeometry.paneFrame` 一致）。
    static func paneIndex(
        windowFrame: CGRect,
        paneFrames: [CGRect],
        lastFocusedPaneIndex: Int,
        paneWindowCounts: [Int]
    ) -> Int? {
        guard !paneFrames.isEmpty, paneFrames.count == paneWindowCounts.count else {
            return nil
        }

        if let hit = uniquePane(
            containing: CGPoint(x: windowFrame.midX, y: windowFrame.midY),
            in: paneFrames
        ) {
            return hit
        }

        if let overlap = uniquelyLargestOverlapIndex(
            windowFrame: windowFrame,
            paneFrames: paneFrames
        ) {
            return overlap
        }

        return focusedOrLeastFull(
            lastFocusedPaneIndex: lastFocusedPaneIndex,
            paneWindowCounts: paneWindowCounts
        )
    }

    private static func uniquePane(containing point: CGPoint, in paneFrames: [CGRect]) -> Int? {
        let hits = paneFrames.indices.filter { paneFrames[$0].contains(point) }
        return hits.count == 1 ? hits[0] : nil
    }

    private static func uniquelyLargestOverlapIndex(
        windowFrame: CGRect,
        paneFrames: [CGRect]
    ) -> Int? {
        let areas = paneFrames.map { intersectionArea(windowFrame, $0) }
        guard let best = areas.enumerated().max(by: { $0.element < $1.element }),
              best.element > 0
        else {
            return nil
        }

        let tied = areas.indices.filter { areas[$0] == best.element }
        return tied.count == 1 ? best.offset : nil
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isInfinite else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private static func focusedOrLeastFull(
        lastFocusedPaneIndex: Int,
        paneWindowCounts: [Int]
    ) -> Int? {
        guard !paneWindowCounts.isEmpty else { return nil }
        if paneWindowCounts.indices.contains(lastFocusedPaneIndex) {
            return lastFocusedPaneIndex
        }
        return paneWindowCounts.indices.min(by: {
            paneWindowCounts[$0] < paneWindowCounts[$1]
        })
    }
}

enum WindowSettle {
    static let maxGeometryDelta: CGFloat = 12
    static let requiredStableReads = 3

    /// 连续读到几乎不动的 frame 则累加；一旦明显移动就清零。
    static func nextStableCount(previous: CGRect, current: CGRect, stableCount: Int) -> Int {
        WindowIndexer.geometryDelta(previous, current) <= maxGeometryDelta ? stableCount + 1 : 0
    }

    static func isSettled(_ stableCount: Int) -> Bool {
        stableCount >= requiredStableReads
    }
}

enum PaneFrameFit {
    static let originSlop: CGFloat = 32
    static let sizeSlop: CGFloat = 40

    /// Chrome 等会带边框 inset；只要已经铺进格位就视为成功，避免无限重试。
    static func matches(_ actual: CGRect, expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= originSlop
            && abs(actual.minY - expected.minY) <= originSlop
            && abs(actual.width - expected.width) <= sizeSlop
            && abs(actual.height - expected.height) <= sizeSlop
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
