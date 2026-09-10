import CoreGraphics
import Testing
@testable import RightScreen

struct StatusItemPresenceTests {
    @Test func parkedWhenBelowMenuBar() {
        #expect(StatusItemPresence.isParkedOffMenuBar(windowFrame: CGRect(x: 0, y: -22, width: 28, height: 22)))
    }

    @Test func parkedWhenDegenerateSize() {
        #expect(StatusItemPresence.isParkedOffMenuBar(windowFrame: CGRect(x: 100, y: 800, width: 0, height: 22)))
    }

    @Test func visibleWhenOnMenuBar() {
        #expect(!StatusItemPresence.isParkedOffMenuBar(windowFrame: CGRect(x: 1200, y: 1054, width: 28, height: 24)))
    }
}

#if os(macOS)
import AppKit

struct StatusItemIconTests {
    @Test func statusBarImageIsTemplateAndSized() {
        let image = LayoutKindIcon.statusBarImage()
        #expect(image.isTemplate)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }
}
#endif
