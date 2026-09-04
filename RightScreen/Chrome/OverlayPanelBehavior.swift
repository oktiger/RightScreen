import AppKit

/// 布局浮层的公共基类。插拔显示器时系统会用 `constrainFrameRect` 把窗口
/// 「纠正」回可见区域，Tab 条会相对内容窗一点点漂走；这里保持调用方给出的坐标。
class OverlayPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

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
        isRestorable = false
        animationBehavior = .none
        collectionBehavior = [
            .transient,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
    }
}
