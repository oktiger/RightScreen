import Testing
@testable import RightScreen

struct PaneMoveTests {
    @Test func fullScreenOffersNoMoves() {
        #expect(PaneMove.availableDirections(from: 0, kind: .fullScreen).isEmpty)
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .right, kind: .fullScreen) == nil)
    }

    @Test func split2OnlyOffersHorizontalNeighbors() {
        #expect(PaneMove.availableDirections(from: 0, kind: .split2) == [.right])
        #expect(PaneMove.availableDirections(from: 1, kind: .split2) == [.left])
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .left, kind: .split2) == nil)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .right, kind: .split2) == nil)
    }

    @Test func split3OnlyOffersHorizontalNeighbors() {
        #expect(PaneMove.availableDirections(from: 0, kind: .split3) == [.right])
        #expect(PaneMove.availableDirections(from: 1, kind: .split3) == [.left, .right])
        #expect(PaneMove.availableDirections(from: 2, kind: .split3) == [.left])
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .right, kind: .split3) == 1)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .left, kind: .split3) == 0)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .right, kind: .split3) == 2)
        #expect(PaneMove.destinationPaneIndex(from: 2, direction: .left, kind: .split3) == 1)
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .left, kind: .split3) == nil)
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .up, kind: .split3) == nil)
        #expect(PaneMove.destinationPaneIndex(from: 2, direction: .right, kind: .split3) == nil)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .down, kind: .split3) == nil)
    }

    @Test func topBottomOnlyOffersVerticalNeighbors() {
        #expect(PaneMove.availableDirections(from: 0, kind: .topBottom) == [.down])
        #expect(PaneMove.availableDirections(from: 1, kind: .topBottom) == [.up])
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .right, kind: .topBottom) == nil)
    }

    @Test func focusStackRightFromLeftLandsOnTopRight() {
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .right, kind: .focusStack) == 1)
        #expect(PaneMove.availableDirections(from: 0, kind: .focusStack) == [.right])
        #expect(PaneMove.availableDirections(from: 1, kind: .focusStack) == [.left, .down])
        #expect(PaneMove.availableDirections(from: 2, kind: .focusStack) == [.left, .up])
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .down, kind: .focusStack) == 2)
        #expect(PaneMove.destinationPaneIndex(from: 2, direction: .left, kind: .focusStack) == 0)
    }

    @Test func stackFocusLeftFromRightLandsOnTopLeft() {
        #expect(PaneMove.destinationPaneIndex(from: 2, direction: .left, kind: .stackFocus) == 0)
        #expect(PaneMove.availableDirections(from: 0, kind: .stackFocus) == [.right, .down])
        #expect(PaneMove.availableDirections(from: 1, kind: .stackFocus) == [.right, .up])
        #expect(PaneMove.availableDirections(from: 2, kind: .stackFocus) == [.left])
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .down, kind: .stackFocus) == 1)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .right, kind: .stackFocus) == 2)
    }

    @Test func split4OffersTwoAdjacentDirectionsPerCorner() {
        #expect(PaneMove.availableDirections(from: 0, kind: .split4) == [.right, .down])
        #expect(PaneMove.availableDirections(from: 1, kind: .split4) == [.left, .down])
        #expect(PaneMove.availableDirections(from: 2, kind: .split4) == [.right, .up])
        #expect(PaneMove.availableDirections(from: 3, kind: .split4) == [.left, .up])
    }

    @Test func split4DestinationMappingMatchesGrid() {
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .right, kind: .split4) == 1)
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .down, kind: .split4) == 2)
        #expect(PaneMove.destinationPaneIndex(from: 3, direction: .left, kind: .split4) == 2)
        #expect(PaneMove.destinationPaneIndex(from: 3, direction: .up, kind: .split4) == 1)
    }
}
