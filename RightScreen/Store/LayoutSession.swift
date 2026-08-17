import AppKit
import CoreGraphics

struct PaneState {
    let geometry: PaneGeometry
    var windows: [ManagedWindow]
    var selectedIndex: Int
}

@MainActor
final class LayoutSession {
    let kind: LayoutKind
    let screen: NSScreen
    var originalFrames: [CGWindowID: CGRect]
    var panes: [PaneState]
    var panels: [PaneTabBarPanel?]
    var lastFocusedPaneIndex: Int = 0

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
            PaneState(geometry: geometry, windows: windows, selectedIndex: 0)
        }
        panels = Array(repeating: nil, count: panes.count)
    }
}
