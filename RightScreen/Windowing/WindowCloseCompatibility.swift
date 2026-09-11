/// 个别 App 的 Accessibility 标题栏实现不完整时使用的关闭兼容策略。
///
/// 必须以 bundle identifier 精确匹配，避免把 App 内部菜单命令误用于其它程序。
enum WindowCloseCompatibility {
    case menuCloseCommand

    static func strategy(for bundleIdentifier: String?) -> Self? {
        switch bundleIdentifier {
        // Shadowrocket 是 Mac Catalyst App。其 AXCloseButton 可以报告成功却不
        // 实际关闭窗口；菜单项 `performClose:` 是该 App 稳定提供的关闭入口。
        case "com.liguangming.Shadowrocket":
            return .menuCloseCommand
        default:
            return nil
        }
    }
}
