import CoreGraphics
import Foundation

/// RightScreen 需要用户在系统设置里授予的权限。新增权限时在这里加 case，引导窗口会多出一行。
enum AppPermission: CaseIterable, Identifiable {
    /// 移动、缩放、聚焦其他 App 的窗口（AX），以及全局快捷键兜底监听。
    case accessibility

    var id: Self { self }

    /// 系统设置里对应列表的名称。macOS 27 起「辅助功能」更名为「设备控制和数据访问」。
    func settingsName(osMajorVersion: Int) -> String {
        switch self {
        case .accessibility:
            osMajorVersion >= 27 ? localized("设备控制和数据访问") : localized("辅助功能")
        }
    }

    var settingsName: String {
        settingsName(osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    var purpose: String {
        switch self {
        case .accessibility: localized("移动和调整其他 App 的窗口")
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility: "macwindow.on.rectangle"
        }
    }

    /// 依次尝试，直达该权限的列表页。
    var settingsURLs: [String] {
        switch self {
        case .accessibility:
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ]
        }
    }
}

/// 授权提示条在系统设置窗口里的位置（AppKit 坐标）。
///
/// 系统设置左侧是约 232pt 的侧边栏，右侧权限列表下方到窗口底边留有约 52pt 空白；
/// 提示条放在这块空白里、相对右侧内容区水平居中，看起来就在列表正下方。
enum PermissionHelperPlacement {
    static let sidebarWidth: CGFloat = 232
    static let bottomInset: CGFloat = 8
    static let horizontalInset: CGFloat = 12

    /// 提示条最大宽度：不超出右侧内容区。
    static func maxWidth(settingsFrame: CGRect) -> CGFloat {
        detailPane(of: settingsFrame).width - horizontalInset * 2
    }

    static func frame(panelSize: CGSize, settingsFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let pane = detailPane(of: settingsFrame)
        let width = min(panelSize.width, maxWidth(settingsFrame: settingsFrame))
        var x = pane.midX - width / 2
        var y = settingsFrame.minY + bottomInset
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        return CGRect(x: x, y: y, width: width, height: panelSize.height)
    }

    private static func detailPane(of settingsFrame: CGRect) -> CGRect {
        let sidebar = min(sidebarWidth, settingsFrame.width / 3)
        return CGRect(
            x: settingsFrame.minX + sidebar,
            y: settingsFrame.minY,
            width: settingsFrame.width - sidebar,
            height: settingsFrame.height
        )
    }
}
