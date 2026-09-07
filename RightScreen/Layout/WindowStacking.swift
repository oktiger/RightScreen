import CoreGraphics

/// 决定激活某个窗口之后，哪些可见窗口需要再抬一次，用来盖住同应用被连带抬起的兄弟窗口。
enum WindowStacking {
    /// 其他格（或网格其他叶）里当前可见、且不属于 `focused` 同一进程的窗口。
    ///
    /// 同进程窗口会被 `NSRunningApplication.activate()` / Chrome 激活时整组前置；
    /// 把这些窗口重新 raise 会再次抬高兄弟窗口，所以必须跳过。
    static func coveringWindows(
        keepingFront focused: ManagedWindow,
        visibleWindows: [ManagedWindow]
    ) -> [ManagedWindow] {
        visibleWindows.filter { window in
            window.ownerPID != focused.ownerPID
        }
    }

    /// CG 前→后窗口栈里的一项，只保留判断遮挡需要的字段。
    struct StackEntry: Equatable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let frame: CGRect

        init(windowID: CGWindowID, ownerPID: pid_t, frame: CGRect) {
            self.windowID = windowID
            self.ownerPID = ownerPID
            self.frame = frame
        }
    }

    /// 只有当 `focused` 所属应用的兄弟窗口确实压在别的格上面时，才需要重新叠放。
    ///
    /// 无条件 raise 会把前台进程切来切去，每次切换又发回激活通知，
    /// 于是「raise → 通知 → 再 raise」自激循环，屏幕看起来在闪。
    /// 先读一次 CG 的真实前后顺序，没有遮挡就什么都不做，循环自然收敛。
    static func windowsNeedingRestack(
        keepingFront focused: ManagedWindow,
        visibleWindows: [ManagedWindow],
        stack: [StackEntry]
    ) -> [ManagedWindow] {
        let candidates = coveringWindows(keepingFront: focused, visibleWindows: visibleWindows)
        guard !candidates.isEmpty else { return [] }

        var indexByWindowID: [CGWindowID: Int] = [:]
        for (index, entry) in stack.enumerated() where indexByWindowID[entry.windowID] == nil {
            indexByWindowID[entry.windowID] = index
        }

        return candidates.filter { candidate in
            // 不在当前 Space 的可见栈里，就谈不上被盖住。
            guard let candidateIndex = indexByWindowID[candidate.windowID] else { return false }
            let candidateFrame = stack[candidateIndex].frame
            return stack.prefix(candidateIndex).contains { entry in
                entry.ownerPID == focused.ownerPID
                    && entry.windowID != focused.windowID
                    && occludes(entry.frame, candidateFrame)
            }
        }
    }

    private static func occludes(_ intruder: CGRect, _ target: CGRect) -> Bool {
        let targetArea = target.width * target.height
        guard targetArea > 0 else { return false }
        let intersection = intruder.intersection(target)
        guard !intersection.isNull, !intersection.isInfinite else { return false }
        return (intersection.width * intersection.height) / targetArea >= 0.05
    }
}
