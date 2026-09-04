import CoreGraphics
import Testing
@testable import RightScreen

struct ScreenChangeLayoutTests {
    @Test func tabBarFollowsVisibleFrameWhenScreenOriginShifts() {
        let before = CGRect(x: 0, y: 50, width: 1440, height: 850)
        let after = CGRect(x: 0, y: -130, width: 1440, height: 850)
        let original = LayoutEngine.geometries(for: .fullScreen, in: before)
        let relaidOut = LayoutEngine.geometries(for: .fullScreen, in: after)

        #expect(relaidOut[0].tabBarFrame.origin.y == original[0].tabBarFrame.origin.y - 180)
        #expect(relaidOut[0].windowFrame.origin.y == original[0].windowFrame.origin.y - 180)
        #expect(relaidOut[0].tabBarFrame.size == original[0].tabBarFrame.size)
    }

    @Test func split2TabBarsKeepRelativePlacementAfterOriginShift() {
        let before = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 0, y: 50, width: 1440, height: 850)
        )
        let after = LayoutEngine.geometries(
            for: .split2,
            in: CGRect(x: 120, y: -130, width: 1920, height: 1030)
        )

        #expect(before.count == after.count)
        #expect(after[0].tabBarFrame.maxY == after[0].paneFrame.maxY)
        #expect(after[1].tabBarFrame.maxY == after[1].paneFrame.maxY)
        #expect(after[0].paneFrame.maxX == after[1].paneFrame.minX)
    }

    @Test func accessibilityYUsesPrimaryScreenNotTheLayoutScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let laptop = CGRect(x: 240, y: -900, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 240, y: -900, width: 1440, height: 850)
        let tabBar = LayoutEngine.geometries(for: .fullScreen, in: visibleFrame)[0].tabBarFrame

        let correct = ScreenFrameConversion.flippingY(tabBar, relativeTo: primary)
        let usingLayoutScreen = ScreenFrameConversion.flippingY(tabBar, relativeTo: laptop)

        #expect(correct.origin.y == primary.maxY - tabBar.maxY)
        #expect(correct.origin.y != usingLayoutScreen.origin.y)
    }

    @Test func preferredScreenFollowsTheDisplayWithMostWindowArea() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: -900, width: 1440, height: 900)
        ]
        let windows = [CGRect(x: 40, y: -800, width: 800, height: 600)]

        #expect(ScreenIdentity.preferredScreenIndex(screenFrames: screens, windowFrames: windows) == 1)
    }

    @Test func preferredScreenIsNilWhenWindowsMissEveryDisplay() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let windows = [CGRect(x: 4000, y: 0, width: 200, height: 200)]

        #expect(ScreenIdentity.preferredScreenIndex(screenFrames: screens, windowFrames: windows) == nil)
    }
}
