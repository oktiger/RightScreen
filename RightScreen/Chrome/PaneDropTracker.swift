import AppKit

/// 用当前鼠标位置（不监听全部按键）判断跨格拖放，避免 Input Monitoring。
@MainActor
final class PaneDropTracker {
    private static let pollInterval: TimeInterval = 1.0 / 30.0

    private let overlay = PaneDropOverlayPanel()
    private var timer: Timer?
    private var paneFrames: [CGRect] = []
    private var isDragging = false
    private var originPoint: CGPoint?
    private var originPaneIndex: Int?
    private var highlightedPaneIndex: Int?

    var onDropInPane: ((Int) -> Void)?

    func start(paneFrames: [CGRect]) {
        self.paneFrames = paneFrames
        timer?.invalidate()
        resetDragState()
        overlay.hideOverlay()
        timer = Timer.scheduledTimer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(pollMouse),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = 0.01
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetDragState()
        overlay.hideOverlay()
        onDropInPane = nil
    }

    func updatePaneFrames(_ frames: [CGRect]) {
        paneFrames = frames
    }

    private func resetDragState() {
        isDragging = false
        originPoint = nil
        originPaneIndex = nil
        highlightedPaneIndex = nil
    }

    @objc private func pollMouse() {
        let leftDown = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
        let location = NSEvent.mouseLocation

        if leftDown {
            if !isDragging {
                isDragging = true
                originPoint = location
                originPaneIndex = NewWindowPlacement.paneIndex(containing: location, in: paneFrames)
                highlightedPaneIndex = nil
                overlay.hideOverlay()
                return
            }

            let highlight = PaneDropHighlight.targetPaneIndex(
                originPaneIndex: originPaneIndex,
                cursor: location,
                originPoint: originPoint,
                paneFrames: paneFrames
            )
            if highlight != highlightedPaneIndex {
                highlightedPaneIndex = highlight
                if let highlight, paneFrames.indices.contains(highlight) {
                    overlay.show(over: paneFrames[highlight])
                } else {
                    overlay.hideOverlay()
                }
            }
            return
        }

        if isDragging {
            let target = highlightedPaneIndex
            resetDragState()
            overlay.hideOverlay()
            if let target {
                onDropInPane?(target)
            }
        }
    }
}

enum PaneDropHighlight {
    static let dragSlop: CGFloat = 8

    /// 从一格拖到另一格且超过拖动阈值时，返回当前光标所在格。
    static func targetPaneIndex(
        originPaneIndex: Int?,
        cursor: CGPoint,
        originPoint: CGPoint?,
        paneFrames: [CGRect],
        slop: CGFloat = dragSlop
    ) -> Int? {
        if let originPoint {
            let dx = cursor.x - originPoint.x
            let dy = cursor.y - originPoint.y
            guard (dx * dx + dy * dy) >= slop * slop else { return nil }
        }
        guard let current = NewWindowPlacement.paneIndex(containing: cursor, in: paneFrames) else {
            return nil
        }
        guard let originPaneIndex, current != originPaneIndex else { return nil }
        return current
    }
}
