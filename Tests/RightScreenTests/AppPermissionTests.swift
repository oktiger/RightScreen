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
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 400, height: 76)

    @Test func sitsCenteredBelowSettingsWhenThereIsRoom() {
        let settings = CGRect(x: 400, y: 300, width: 700, height: 500)
        let frame = PermissionHelperPlacement.frame(panelSize: size, settingsFrame: settings, visibleFrame: visible)
        #expect(frame.midX == settings.midX)
        #expect(frame.maxY == settings.minY - PermissionHelperPlacement.gap)
    }

    @Test func movesBesideSettingsWhenBottomIsFull() {
        let settings = CGRect(x: 200, y: 20, width: 700, height: 800)
        let frame = PermissionHelperPlacement.frame(panelSize: size, settingsFrame: settings, visibleFrame: visible)
        #expect(frame.minX == settings.maxX + PermissionHelperPlacement.gap)
        #expect(visible.contains(frame))
    }

    @Test func fallsBackInsideSettingsWhenScreenIsFull() {
        let settings = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = PermissionHelperPlacement.frame(panelSize: size, settingsFrame: settings, visibleFrame: visible)
        #expect(settings.contains(frame))
        #expect(frame.minY == PermissionHelperPlacement.gap)
    }
}
