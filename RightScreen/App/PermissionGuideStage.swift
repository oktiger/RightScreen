import Foundation

/// 权限引导窗口当前应展示的阶段；纯函数推导，便于单测。
enum PermissionGuideStage: Equatable {
    /// 安装包签名或 Bundle ID 不对，授权无法生效。
    case signingIssue(String)
    /// 尚未授权，用户还没去系统设置。
    case needsGrant
    /// 已打开系统设置，等待用户打开开关。
    case waitingForToggle
    /// 打开系统设置已久仍未生效：多半是残留了旧版本的授权记录。
    case stuck
    case granted

    static let stuckThreshold: TimeInterval = 10

    static func resolve(
        signingIssue: String?,
        isTrusted: Bool,
        secondsSinceSettingsOpened: TimeInterval?
    ) -> PermissionGuideStage {
        if let signingIssue {
            return .signingIssue(signingIssue)
        }
        if isTrusted {
            return .granted
        }
        guard let elapsed = secondsSinceSettingsOpened else {
            return .needsGrant
        }
        return elapsed >= stuckThreshold ? .stuck : .waitingForToggle
    }
}
