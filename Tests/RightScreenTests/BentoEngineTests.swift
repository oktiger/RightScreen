import CoreGraphics
import Testing
@testable import RightScreen

struct BentoEngineTests {
    @Test func oneWindowIsSingleLeaf() {
        let tree = BentoEngine.buildTree(["A"])
        #expect(BentoEngine.leafValues(tree!) == ["A"])

        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = BentoEngine.layout(tree!, in: frame, gap: 8)
        #expect(layout.leaves.count == 1)
        #expect(layout.leaves[0].frame == frame)
        #expect(layout.dividers.isEmpty)
    }

    @Test func twoWindowsSplitVertically() {
        let tree = BentoEngine.buildTree(["A", "B"])!
        let frame = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let layout = BentoEngine.layout(tree, in: frame, gap: 8)

        #expect(layout.leaves.map(\.value) == ["A", "B"])
        #expect(layout.dividers.count == 1)
        #expect(layout.dividers[0].orientation == .vertical)
        #expect(layout.leaves[0].frame.width + 8 + layout.leaves[1].frame.width == 1000)
        #expect(layout.leaves[0].frame.maxX + 8 == layout.leaves[1].frame.minX)
    }

    @Test func threeWindowsBecomeFocusStackShape() {
        let tree = BentoEngine.buildTree(["A", "B", "C"])!
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = BentoEngine.layout(tree, in: frame, gap: 8)
        let leaves = Dictionary(uniqueKeysWithValues: layout.leaves.map { ($0.value, $0.frame) })

        // 左整高 + 右上下。
        #expect(leaves["A"]?.height == 800)
        #expect(leaves["B"]?.maxY == 800)
        #expect(leaves["C"]?.minY == 0)
        #expect(leaves["B"]!.height + 8 + leaves["C"]!.height == 800)
        #expect(leaves["A"]!.maxX + 8 == leaves["B"]!.minX)
    }

    @Test func fourWindowsFormQuadrants() {
        let tree = BentoEngine.buildTree(["A", "B", "C", "D"])!
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = BentoEngine.layout(tree, in: frame, gap: 8)

        #expect(layout.leaves.map(\.value) == ["A", "B", "C", "D"])
        #expect(layout.dividers.count == 3)
    }

    @Test func updatingVerticalRatioChangesWidths() {
        let tree = BentoEngine.buildTree(["A", "B"])!
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let updated = BentoEngine.updatingRatio(
            in: tree,
            path: [],
            location: 300,
            splitFrame: frame,
            gap: 8
        )
        let layout = BentoEngine.layout(updated, in: frame, gap: 8)
        // 显式 CGFloat：与 frame.width 同类型，避免 #expect 宏里 CGFloat/Double 混比误判。
        let expectedFirst: CGFloat = floor(992 * (300.0 / 992.0))
        #expect(layout.leaves[0].frame.width == expectedFirst)
        #expect(layout.leaves[0].frame.width + 8 + layout.leaves[1].frame.width == 1000)
    }

    @Test func ratioIsClampedToMinimumPaneLength() {
        let tree = BentoEngine.buildTree(["A", "B"])!
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let updated = BentoEngine.updatingRatio(
            in: tree,
            path: [],
            location: 10,
            splitFrame: frame,
            gap: 8
        )
        let layout = BentoEngine.layout(updated, in: frame, gap: 8)
        #expect(layout.leaves[0].frame.width >= BentoEngine.minimumPaneLength - 1)
    }
}
