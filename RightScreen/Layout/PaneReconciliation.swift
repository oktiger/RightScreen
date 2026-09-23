import CoreGraphics

/// 已在某个 Tab 布局中、再次点同一布局时的「就地校正」。
///
/// 不重新均分：已经贴合格位的窗口原地不动、顺序不变；
/// 只有跑出格位的窗口按中心点所在格重新归位，归到别的格时追加到该格末尾。
enum PaneReconciliation {
    struct Result: Equatable {
        /// 校正后每格的窗口顺序。
        var panes: [[CGWindowID]]
        /// 换了格的窗口 → 新格下标。
        var movedWindowIDs: [CGWindowID: Int]
    }

    /// - Parameters:
    ///   - panes: 每格当前的窗口 ID（即 Tab 顺序）。
    ///   - currentFrames: 窗口当前 AppKit frame；缺失表示读不到或已最小化，此时留在原格。
    ///   - paneFrames: 各格整格区域（AppKit），用来判断窗口中心落在哪一格。
    ///   - windowFrames: 各格窗口应有的 frame（AppKit），用来判断窗口是否仍贴合原格。
    static func reconcile(
        panes: [[CGWindowID]],
        currentFrames: [CGWindowID: CGRect],
        paneFrames: [CGRect],
        windowFrames: [CGRect]
    ) -> Result {
        guard panes.count == paneFrames.count, panes.count == windowFrames.count else {
            return Result(panes: panes, movedWindowIDs: [:])
        }

        var result = panes
        var moved: [CGWindowID: Int] = [:]

        for (paneIndex, windowIDs) in panes.enumerated() {
            for windowID in windowIDs {
                guard
                    let frame = currentFrames[windowID],
                    !PaneFrameFit.matches(frame, expected: windowFrames[paneIndex]),
                    let target = NewWindowPlacement.paneIndex(
                        containing: CGPoint(x: frame.midX, y: frame.midY),
                        in: paneFrames
                    ),
                    target != paneIndex
                else {
                    continue
                }
                result[paneIndex].removeAll { $0 == windowID }
                result[target].append(windowID)
                moved[windowID] = target
            }
        }

        return Result(panes: result, movedWindowIDs: moved)
    }
}
