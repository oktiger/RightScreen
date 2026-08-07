import Testing
@testable import RightScreen

struct PaneMoveTests {
    @Test func split2OnlyOffersHorizontalNeighbors() {
        #expect(PaneMove.availableDirections(from: 0, kind: .split2) == [.right])
        #expect(PaneMove.availableDirections(from: 1, kind: .split2) == [.left])
        #expect(PaneMove.destinationPaneIndex(from: 0, direction: .left, kind: .split2) == nil)
        #expect(PaneMove.destinationPaneIndex(from: 1, direction: .right, kind: .split2) == nil)
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
