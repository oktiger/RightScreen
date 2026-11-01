import Foundation

/// 重启后要恢复的布局。只记布局种类，窗口归属在恢复时按窗口当前位置重新判断。
enum RememberedLayout: Equatable {
    case tabs(LayoutKind)
    case grid

    private static let gridRawValue = "grid"
    private static let tabsPrefix = "tabs:"

    init?(rawValue: String) {
        if rawValue == Self.gridRawValue {
            self = .grid
        } else if rawValue.hasPrefix(Self.tabsPrefix),
                  let kind = LayoutKind(rawValue: String(rawValue.dropFirst(Self.tabsPrefix.count))) {
            self = .tabs(kind)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .tabs(let kind): Self.tabsPrefix + kind.rawValue
        case .grid: Self.gridRawValue
        }
    }
}

/// 记住当前布局，让 RightScreen 被更新、崩溃或随系统重启后能接着管理窗口。
/// 用户主动退出布局或退出 RightScreen 时清除。
@MainActor
final class LayoutMemory {
    private static let key = "rememberedLayout"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: RememberedLayout? {
        defaults.string(forKey: Self.key).flatMap(RememberedLayout.init(rawValue:))
    }

    func remember(_ layout: RememberedLayout) {
        defaults.set(layout.rawValue, forKey: Self.key)
    }

    func forget() {
        defaults.removeObject(forKey: Self.key)
    }
}
