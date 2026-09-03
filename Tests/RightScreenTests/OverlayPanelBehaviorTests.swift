import AppKit
import Testing
@testable import RightScreen

struct OverlayPanelBehaviorTests {
    @Test @MainActor func overlaySpaceBehaviorDoesNotJoinAllSpaces() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.applyOverlaySpaceBehavior()

        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.collectionBehavior.contains(.stationary))

        panel.close()
    }
}
