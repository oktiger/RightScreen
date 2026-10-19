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

/// 拖动授权浮窗相对系统设置窗口的摆放位置（AppKit 坐标）。
enum PermissionHelperPlacement {
    static let gap: CGFloat = 12

    /// 优先贴在系统设置窗口正下方；放不下时依次尝试右侧、左侧，最后压在窗口底部内侧。
    static func frame(panelSize: CGSize, settingsFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        func clampedX(_ x: CGFloat) -> CGFloat {
            min(max(x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        }
        func clampedY(_ y: CGFloat) -> CGFloat {
            min(max(y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        }

        let below = settingsFrame.minY - gap - panelSize.height
        if below >= visibleFrame.minY {
            return CGRect(origin: CGPoint(x: clampedX(settingsFrame.midX - panelSize.width / 2), y: below), size: panelSize)
        }

        let besideY = clampedY(settingsFrame.minY + gap)
        let right = settingsFrame.maxX + gap
        if right + panelSize.width <= visibleFrame.maxX {
            return CGRect(origin: CGPoint(x: right, y: besideY), size: panelSize)
        }
        let left = settingsFrame.minX - gap - panelSize.width
        if left >= visibleFrame.minX {
            return CGRect(origin: CGPoint(x: left, y: besideY), size: panelSize)
        }

        return CGRect(
            origin: CGPoint(x: clampedX(settingsFrame.midX - panelSize.width / 2), y: clampedY(settingsFrame.minY + gap)),
            size: panelSize
        )
    }
}
