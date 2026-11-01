import ApplicationServices
import CoreGraphics

struct ManagedWindow {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    let frame: CGRect
    let element: AXUIElement

    func refersToSameAccessibilityWindow(as other: ManagedWindow) -> Bool {
        ownerPID == other.ownerPID && CFEqual(element, other.element)
    }

    /// 窗口标题会随页面切换而变化（Electron 窗口刚创建时常先报应用名），
    /// 布局里保存的窗口需要用最新标题替换旧值。
    func withTitle(_ newTitle: String) -> ManagedWindow {
        ManagedWindow(
            windowID: windowID,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: newTitle,
            frame: frame,
            element: element
        )
    }

    var tabTitle: String {
        let trimmedWindowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWindowTitle.isEmpty {
            return trimmedWindowTitle
        }

        return appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
