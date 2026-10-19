import CoreGraphics
import Testing
@testable import RightScreen

struct AppPermissionTests {
    @Test func accessibilityListWasRenamedInMacOS27() {
        #expect(AppPermission.accessibility.settingsName(osMajorVersion: 26) == "辅助功能")
        #expect(AppPermission.accessibility.settingsName(osMajorVersion: 27) == "设备控制和数据访问")
    }

    @Test func settingsURLsTargetTheAccessibilityAnchor() {
        #expect(AppPermission.accessibility.settingsURLs.allSatisfy { $0.hasSuffix("?Privacy_Accessibility") })
    }
}

struct PermissionHelperPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
    // 实测 macOS 27 系统设置窗口：740×690，侧边栏 232pt。
    private let settings = CGRect(x: 1216, y: 61, width: 740, height: 690)

    @Test func sitsUnderTheListCenteredInTheDetailPane() {
        let frame = PermissionHelperPlacement.frame(
            panelSize: CGSize(width: 360, height: 36),
            settingsFrame: settings,
            visibleFrame: visible
        )
        #expect(frame.midX == settings.minX + 232 + (740 - 232) / 2)
        #expect(frame.minY == settings.minY + PermissionHelperPlacement.bottomInset)
        // 列表底部距窗口底边约 52pt，提示条不能盖住列表。
        #expect(frame.maxY <= settings.minY + 52)
    }

    @Test func longTextIsClampedToTheDetailPane() {
        let frame = PermissionHelperPlacement.frame(
            panelSize: CGSize(width: 900, height: 36),
            settingsFrame: settings,
            visibleFrame: visible
        )
        #expect(frame.width == 740 - 232 - PermissionHelperPlacement.horizontalInset * 2)
        #expect(frame.minX >= settings.minX + 232)
    }

    @Test func staysOnScreenWhenSettingsHangsOffTheBottom() {
        let low = CGRect(x: 100, y: -300, width: 740, height: 690)
        let frame = PermissionHelperPlacement.frame(
            panelSize: CGSize(width: 360, height: 36),
            settingsFrame: low,
            visibleFrame: visible
        )
        #expect(visible.contains(frame))
    }
}
