import AppKit
import CoreGraphics

struct PaneState {
    let geometry: PaneGeometry
    var windows: [ManagedWindow]
    var selectedIndex: Int
    /// 最近激活的窗口 ID，队首是当前工作窗口。
    var activationHistory: [CGWindowID] = []

    mutating func recordActivation(of window: ManagedWindow) {
        activationHistory = PaneTabHistory.recording(window.windowID, in: activationHistory)
    }

    mutating func selectWindow(at index: Int) {
        guard windows.indices.contains(index) else { return }
        selectedIndex = index
        recordActivation(of: windows[index])
    }

    mutating func selectAfterRemoving(windowID: CGWindowID, at removedIndex: Int) {
        activationHistory = PaneTabHistory.removing(windowID, from: activationHistory)
        if windows.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = PaneTabHistory.selectedIndex(
                remainingIDs: windows.map(\.windowID),
                history: activationHistory,
                removedIndex: removedIndex
            )
        }
    }
}

@MainActor
final class LayoutSession {
    var kind: LayoutKind
    let screen: NSScreen
    var originalFrames: [CGWindowID: CGRect]
    var panes: [PaneState]
    var panels: [PaneTabBarPanel?]
    var lastFocusedPaneIndex: Int = 0
    /// 自动并入、尚未被用户点选 Tab 的窗口。把它们换到邻格时，焦点回到源格上一工作窗口。
    var autoJoinedWindowIDs = Set<CGWindowID>()

    init(
        kind: LayoutKind,
        screen: NSScreen,
        windowsByPane: [[ManagedWindow]],
        geometries: [PaneGeometry]
    ) {
        self.kind = kind
        self.screen = screen
        originalFrames = Dictionary(uniqueKeysWithValues: windowsByPane.flatMap { $0 }.map {
            ($0.windowID, $0.frame)
        })
        panes = zip(geometries, windowsByPane).map { geometry, windows in
            let history = windows.first.map { [$0.windowID] } ?? []
            return PaneState(
                geometry: geometry,
                windows: windows,
                selectedIndex: 0,
                activationHistory: history
            )
        }
        panels = Array(repeating: nil, count: panes.count)
    }
}
