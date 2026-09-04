import AppKit
import CoreGraphics

struct BentoTilePresentation: Equatable {
    let title: String
    let ownerPID: pid_t
    let frame: CGRect

    var applicationIcon: NSImage? {
        NSRunningApplication(processIdentifier: ownerPID)?.icon
    }

    var dimensionText: String {
        "\(Int(frame.width.rounded())) × \(Int(frame.height.rounded()))"
    }
}

@MainActor
final class BentoSession {
    var screen: NSScreen
    var displayID: CGDirectDisplayID
    let gap: CGFloat
    var originalFrames: [CGWindowID: CGRect]
    var tree: BentoNode<ManagedWindow>
    var dividerController: BentoDividerController?
    var previewPanel: BentoPreviewPanel?
    var isDraggingDivider = false

    var rootFrame: CGRect {
        screen.visibleFrame
    }

    init(
        screen: NSScreen,
        windows: [ManagedWindow],
        tree: BentoNode<ManagedWindow>,
        gap: CGFloat = BentoEngine.defaultGap
    ) {
        self.screen = screen
        self.displayID = ScreenIdentity.displayID(of: screen)
        self.gap = gap
        self.tree = tree
        originalFrames = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0.frame) })
    }

    func leafLayouts() -> [BentoLeafLayout<ManagedWindow>] {
        BentoEngine.layout(tree, in: rootFrame, gap: gap).leaves
    }

    func dividerLayouts() -> [BentoDividerLayout] {
        BentoEngine.layout(tree, in: rootFrame, gap: gap).dividers
    }

    func tilePresentations() -> [BentoTilePresentation] {
        leafLayouts().map { leaf in
            BentoTilePresentation(
                title: leaf.value.tabTitle,
                ownerPID: leaf.value.ownerPID,
                frame: leaf.frame
            )
        }
    }
}
