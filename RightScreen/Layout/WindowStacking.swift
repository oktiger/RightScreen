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
}
