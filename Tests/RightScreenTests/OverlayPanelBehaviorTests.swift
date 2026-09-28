import AppKit
import Testing
@testable import RightScreen

struct OverlayPanelBehaviorTests {
    @Test @MainActor func overlaySpaceBehaviorStaysOutOfNativeFullScreen() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.applyOverlaySpaceBehavior()

        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.fullScreenNone))
        #expect(!panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(!panel.isRestorable)

        panel.close()
    }

    @Test @MainActor func overlayPanelDoesNotClampFrameDuringScreenChanges() {
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let proposed = CGRect(x: -120, y: -80, width: 200, height: 32)

        #expect(panel.constrainFrameRect(proposed, to: nil) == proposed)

        panel.close()
    }

    @Test @MainActor func tabBarPanelMovesWhenAvailableFrameOriginShifts() {
        let original = CGRect(x: 20, y: 800, width: 600, height: 32)
        let shifted = CGRect(x: 20, y: 620, width: 600, height: 32)
        let tabs = [PaneTabPresentation(title: "Safari", ownerPID: 1)]
        let panel = PaneTabBarPanel(
            frame: original,
            tabs: tabs,
            moveDirections: [],
            selectionHandler: { _ in },
            closeHandler: { _ in },
            moveHandler: { _, _ in }
        )

        #expect(panel.frame.origin == original.origin)

        panel.updateTabs(tabs, selectedIndex: 0, frame: shifted)

        #expect(panel.frame.origin == shifted.origin)
        #expect(panel.frame.height == shifted.height)

        panel.close()
    }
}
