import ApplicationServices

enum WindowCloseResult: Equatable {
    case requested
    case windowUnavailable
    case blockedByModalDialog
    case temporarilyUnavailable
    case accessibilityPermissionRequired
    case unsupported
    case failed

    static func classify(actionError: AXError, hasBlockingModalUI: Bool) -> Self {
        if actionError == .success {
            return .requested
        }
        if actionError == .invalidUIElement {
            return .windowUnavailable
        }
        if actionError == .apiDisabled {
            return .accessibilityPermissionRequired
        }
        if hasBlockingModalUI {
            return .blockedByModalDialog
        }
        if actionError == .cannotComplete {
            return .temporarilyUnavailable
        }
        if actionError == .actionUnsupported
            || actionError == .attributeUnsupported
            || actionError == .notImplemented
            || actionError == .noValue {
            return .unsupported
        }
        return .failed
    }
}
