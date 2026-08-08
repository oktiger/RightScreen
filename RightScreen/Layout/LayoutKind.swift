/// Tabbed Layout 预设。顺序与状态栏菜单一致。
enum LayoutKind: String, CaseIterable, Sendable {
    /// 单格全屏。
    case fullScreen
    /// 左右二分。
    case split2
    /// 上下二分。
    case topBottom
    /// 左侧主栏 + 右侧上下堆叠（3 格）。
    case focusStack
    /// 四角等分。
    case split4

    var paneCount: Int {
        switch self {
        case .fullScreen: 1
        case .split2, .topBottom: 2
        case .focusStack: 3
        case .split4: 4
        }
    }

    var menuTitle: String {
        switch self {
        case .fullScreen: "全屏"
        case .split2: "左右二分"
        case .topBottom: "上下二分"
        case .focusStack: "主栏 + 堆叠"
        case .split4: "四等分"
        }
    }

    var menuSubtitle: String {
        "\(paneCount) 格"
    }
}
