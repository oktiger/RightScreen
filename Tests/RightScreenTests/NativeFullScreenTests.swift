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

    @Test func paneSizedWindowIsNotNativeFullScreen() {
        let pane = CGRect(x: 0, y: 38, width: 720, height: 830)

        #expect(!NativeFullScreen.coversDisplay(pane, displays: [display]))
    }

    @Test func emptyOrZeroFrameIsNotNativeFullScreen() {
        #expect(!NativeFullScreen.coversDisplay(.zero, displays: [display]))
        #expect(!NativeFullScreen.coversDisplay(display, displays: []))
    }
}
