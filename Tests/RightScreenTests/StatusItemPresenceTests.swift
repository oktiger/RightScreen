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

    /// 系统拒绝分配槽位时的兜底形态：贴在屏幕右缘，且比菜单栏矮。
    @Test func parkedWhenPinnedToRightEdgeAndShorterThanMenuBar() {
        #expect(StatusItemPresence.isParkedOffMenuBar(
            windowFrame: CGRect(x: 3402, y: 1418, width: 38, height: 22),
            screenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            menuBarHeight: 30
        ))
    }

    /// 真正的槽位与菜单栏等高，即便排在最右侧也不算被停靠。
    @Test func notParkedWhenSlotMatchesMenuBarHeight() {
        #expect(!StatusItemPresence.isParkedOffMenuBar(
            windowFrame: CGRect(x: 3402, y: 1410, width: 38, height: 30),
            screenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            menuBarHeight: 30
        ))
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
