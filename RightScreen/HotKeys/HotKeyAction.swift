enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case fullScreen

    var title: String {
        switch self {
        case .moveLeft: "移到左侧"
        case .moveRight: "移到右侧"
        case .moveUp: "移到上方"
        case .moveDown: "移到下方"
        case .fullScreen: "全屏"
        }
    }

    var paneMoveDirection: PaneMoveDirection? {
        switch self {
        case .moveLeft: .left
        case .moveRight: .right
        case .moveUp: .up
        case .moveDown: .down
        case .fullScreen: nil
        }
    }

    var settingsSection: HotKeySettingsSection {
        switch self {
        case .moveLeft, .moveRight, .moveUp, .moveDown: .moveWindow
        case .fullScreen: .layout
        }
    }
}

enum HotKeySettingsSection: String, CaseIterable, Sendable {
    case moveWindow
    case layout

    var title: String {
        switch self {
        case .moveWindow: "移动窗口"
        case .layout: "布局"
        }
    }

    var footer: String? {
        switch self {
        case .moveWindow: "仅在 Tab Mode 中生效，效果与 Tab 栏箭头相同。全屏 1 格时，左右快捷键会切换到左右二分。"
        case .layout: nil
        }
    }

    var actions: [HotKeyAction] {
        HotKeyAction.allCases.filter { $0.settingsSection == self }
    }
}
