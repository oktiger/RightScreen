import AppKit

extension NSPanel {
    /// 浮层只留在当前 Space，且不进入 Mission Control / 窗口循环。
    ///
    /// 禁止 `canJoinAllSpaces`：WindowServer 在 Chrome 等进入原生全屏、
    /// 创建专用 Space 时，会把「加入所有空间」的窗口当成冲突项，
    /// 于是弹出四指上滑那样的 Mission Control，而不是直接切到全屏 Space。
    func applyOverlaySpaceBehavior() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [
            .transient,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
    }
}
