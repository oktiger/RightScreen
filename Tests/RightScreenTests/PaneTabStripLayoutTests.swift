import CoreGraphics
import Testing
@testable import RightScreen

struct PaneTabStripLayoutTests {
    @Test func fewTabsKeepFullWidthAndTitles() {
        let layout = PaneTabStripLayout.make(tabCount: 3, selectedIndex: 0, moveCount: 1, availableWidth: 700)

        #expect(layout.mode == .full)
        #expect(layout.tabWidth == PaneTabStripLayout.maxTabWidth)
        #expect(layout.visibleIndices == [0, 1, 2])
        #expect(!layout.showsOverflow)
    }

    @Test func manyTabsShrinkEvenlyInsteadOfScrolling() {
        let layout = PaneTabStripLayout.make(tabCount: 6, selectedIndex: 0, moveCount: 1, availableWidth: 700)

        #expect(layout.mode == .full)
        #expect(layout.tabWidth < PaneTabStripLayout.maxTabWidth)
        #expect(layout.stripWidth <= 700)
        #expect(layout.visibleIndices.count == 6)
    }

    @Test func titlesDropBeforeMoveButtons() {
        let layout = PaneTabStripLayout.make(tabCount: 9, selectedIndex: 0, moveCount: 1, availableWidth: 700)

        #expect(layout.mode == .iconWithMoves)
        #expect(layout.stripWidth <= 700)
    }

    @Test func moveButtonsDropBeforeOverflow() {
        let layout = PaneTabStripLayout.make(tabCount: 12, selectedIndex: 0, moveCount: 1, availableWidth: 700)

        #expect(layout.mode == .iconOnly)
        #expect(!layout.showsOverflow)
        #expect(layout.stripWidth <= 700)
    }

    @Test func overflowKeepsSelectedTabVisible() {
        let layout = PaneTabStripLayout.make(tabCount: 30, selectedIndex: 25, moveCount: 1, availableWidth: 700)

        #expect(layout.showsOverflow)
        #expect(layout.visibleIndices.contains(25))
        #expect(layout.stripWidth <= 700)
        #expect(Set(layout.visibleIndices + layout.hiddenIndices) == Set(0..<30))
    }
}
