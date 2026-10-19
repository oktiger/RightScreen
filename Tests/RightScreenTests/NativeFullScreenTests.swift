import CoreGraphics
import Testing
@testable import RightScreen

struct NativeFullScreenTests {
    private let display = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func coveringTheDisplayIsNativeFullScreen() {
        let fullscreen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        #expect(NativeFullScreen.coversDisplay(fullscreen, displays: [display]))
    }

    @Test func coveringASecondaryDisplayIsNativeFullScreen() {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let fullscreen = secondary.insetBy(dx: 4, dy: 4)

        #expect(NativeFullScreen.coversDisplay(fullscreen, displays: [display, secondary]))
    }

    @Test func maximizedVisibleFrameIsNotNativeFullScreen() {
        // 菜单栏约 38pt、Dock 约 80pt，普通最大化远低于 96% 整屏覆盖。
        let maximized = CGRect(x: 0, y: 38, width: 1440, height: 782)

        #expect(!NativeFullScreen.coversDisplay(maximized, displays: [display]))
    }

    @Test func maximizedWindowWithHiddenDockIsNotNativeFullScreen() {
        // Dock 自动隐藏：2560×1440 屏、菜单栏 30pt，最大化后覆盖率 97.9%，但顶边在菜单栏下方。
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let maximized = CGRect(x: 0, y: 30, width: 2560, height: 1410)

        #expect(!NativeFullScreen.coversDisplay(maximized, displays: [display]))
    }

    @Test func filledWindowWithTilingMarginsIsNotNativeFullScreen() {
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let filled = CGRect(x: 8, y: 38, width: 2544, height: 1394)

        #expect(!NativeFullScreen.coversDisplay(filled, displays: [display]))
    }

    @Test func maximizedWindowOnSecondaryDisplayIsNotNativeFullScreen() {
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let maximized = CGRect(x: 1440, y: -175, width: 1920, height: 1055)

        #expect(!NativeFullScreen.coversDisplay(maximized, displays: [display, secondary]))
        #expect(NativeFullScreen.coversDisplay(secondary, displays: [display, secondary]))
    }

    @Test func paneSizedWindowIsNotNativeFullScreen() {
        let pane = CGRect(x: 0, y: 38, width: 720, height: 830)

        #expect(!NativeFullScreen.coversDisplay(pane, displays: [display]))
    }

    @Test func emptyOrZeroFrameIsNotNativeFullScreen() {
        #expect(!NativeFullScreen.coversDisplay(.zero, displays: [display]))
        #expect(!NativeFullScreen.coversDisplay(display, displays: []))
    }
}
