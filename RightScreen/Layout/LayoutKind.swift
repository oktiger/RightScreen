/// Tabbed Layout 预设。顺序与状态栏菜单一致。
enum LayoutKind: String, CaseIterable, Sendable {
    /// 单格全屏。
    case fullScreen
    /// 左右二分。
    case split2
    /// 从左到右三等分。
    case split3
    /// 上下二分。
    case topBottom
    /// 1+2：左侧主栏 + 右侧上下堆叠（3 格）。
    case focusStack
    /// 2+1：左侧上下堆叠 + 右侧主栏（3 格，focusStack 镜像）。
    case stackFocus
    /// 四角等分。
    case split4

    var paneCount: Int {
        switch self {
        case .fullScreen: 1
        case .split2, .topBottom: 2
        case .split3, .focusStack, .stackFocus: 3
        case .split4: 4
        }
    }

    var menuTitle: String {
        switch self {
        case .fullScreen: localized("全屏")
        case .split2: localized("左右二分")
        case .split3: localized("左右三等分")
        case .topBottom: localized("上下二分")
        case .focusStack: "1+2"
        case .stackFocus: "2+1"
        case .split4: localized("四等分")
        }
    }

    var menuSubtitle: String {
        // 英文需要区分单复数，1 格单独成键。
        paneCount == 1 ? localized("1 格") : localized("%ld 格", paneCount)
    }
}
