import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowController {
    private static let closeRetryDelays: [Duration] = [
        .zero,
        .milliseconds(50),
        .milliseconds(150)
    ]
    /// 关闭请求发出后，回读窗口是否真的消失的时间上限。
    private static let closeConfirmationTimeout: Duration = .milliseconds(600)
    private static let closeConfirmationPollInterval: Duration = .milliseconds(60)

    func isNativeFullScreen(_ window: ManagedWindow, displays: [CGRect] = NativeFullScreen.displayBounds()) -> Bool {
        NativeFullScreen.isActive(
            element: window.element,
            frame: AXHelpers.frame(of: window.element),
            displays: displays
        )
    }

    @discardableResult
    func setAccessibilityFrame(_ frame: CGRect, for window: ManagedWindow) -> Bool {
        guard isAlive(window) else { return false }
        guard !isNativeFullScreen(window) else { return false }

        let positionResult = AXHelpers.set(
            point: frame.origin,
            attribute: kAXPositionAttribute as CFString,
            on: window.element
        )
        let sizeResult = AXHelpers.set(
            size: frame.size,
            attribute: kAXSizeAttribute as CFString,
            on: window.element
        )
        return positionResult == .success && sizeResult == .success
    }

    /// 窗口被最小化到 Dock 时把它还原。返回 true 表示确实做了还原。
    @discardableResult
    func restoreIfMinimized(_ window: ManagedWindow) -> Bool {
        guard AXHelpers.bool(kAXMinimizedAttribute as CFString, of: window.element) == true else {
            return false
        }
        return AXUIElementSetAttributeValue(
            window.element,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success
    }

    func frameMatches(_ window: ManagedWindow, accessibilityFrame expected: CGRect) -> Bool {
        guard let actual = AXHelpers.frame(of: window.element) else { return false }
        return PaneFrameFit.matches(actual, expected: expected)
    }

    @discardableResult
    func setAppKitFrame(_ frame: CGRect, for window: ManagedWindow) -> Bool {
        setAccessibilityFrame(ScreenIdentity.convertFrame(frame), for: window)
    }

    /// 窗口已经在目标位置时不再写 AX：重复写同一个 frame 也会让 Chrome 等重排一次内容，看起来就是一顿。
    @discardableResult
    func setAppKitFrameIfNeeded(_ frame: CGRect, for window: ManagedWindow) -> Bool {
        let expected = ScreenIdentity.convertFrame(frame)
        if let actual = AXHelpers.frame(of: window.element),
           abs(actual.minX - expected.minX) <= 1,
           abs(actual.minY - expected.minY) <= 1,
           abs(actual.width - expected.width) <= 1,
           abs(actual.height - expected.height) <= 1 {
            return true
        }
        return setAccessibilityFrame(expected, for: window)
    }

    /// 前置窗口。已经关掉的窗口一律不碰。
    ///
    /// 前置必然把窗口所属进程切到前台，系统把这当成「用户切到了这个 App」；
    /// 对已经关掉的窗口这么做会触发 reopen，App 会再开一个窗口回来。
    /// Mac Catalyst App（Shadowrocket）关窗后 AX 元素还在，只有屏幕窗口名单能看出真相。
    @discardableResult
    func raise(_ window: ManagedWindow) -> Bool {
        raise(window, withOnScreenWindowIDs: onScreenWindowIDs())
    }

    /// 批量前置时复用一次读好的屏幕窗口名单。`nil` 表示名单没读到，此时按放行处理。
    @discardableResult
    func raise(_ window: ManagedWindow, withOnScreenWindowIDs listedIDs: Set<CGWindowID>?) -> Bool {
        guard canActivate(window, withOnScreenWindowIDs: listedIDs) else { return false }
        guard !isNativeFullScreen(window) else { return false }

        let ordered = orderFrontWithinApplication(window)

        // `NSRunningApplication.activate()` and `kAXFrontmostAttribute` bring every
        // window of that process forward. Chrome then covers the other pane.
        // Activate with "front window only" after this window is already the app's
        // front window, so siblings stay where they were.
        let activated = ProcessActivation.bringFrontWindowOnly(pid: window.ownerPID)

        return ordered || activated
    }

    /// 这个窗口此刻是否还值得被激活：AX 元素可读，且仍在当前 Space 的屏幕窗口名单里。
    func canActivate(_ window: ManagedWindow) -> Bool {
        canActivate(window, withOnScreenWindowIDs: onScreenWindowIDs())
    }

    /// 复用调用方读好的屏幕窗口名单做同一判断。
    /// `listedIDs == nil` 表示名单没读到，此时不下结论、按可激活处理，
    /// 宁可多前置一次，也不要让正常布局整体卡住。
    func canActivate(_ window: ManagedWindow, withOnScreenWindowIDs listedIDs: Set<CGWindowID>?) -> Bool {
        WindowActivation.allowsActivation(
            isAccessibilityElementAlive: isAlive(window),
            isListedOnScreen: listedIDs?.contains(window.windowID) == true,
            hasOnScreenList: listedIDs != nil
        )
    }

    private func orderFrontWithinApplication(_ window: ManagedWindow) -> Bool {
        let applicationElement = AXUIElementCreateApplication(window.ownerPID)
        let focusedWindowResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window.element
        )
        let mainWindowResult = AXUIElementSetAttributeValue(
            window.element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        let raiseResult = AXUIElementPerformAction(
            window.element,
            kAXRaiseAction as CFString
        )
        return raiseResult == .success
            || focusedWindowResult == .success
            || mainWindowResult == .success
    }

    func close(_ window: ManagedWindow) async -> WindowCloseResult {
        for delay in Self.closeRetryDelays {
            if delay != .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return .temporarilyUnavailable
                }
            }

            let result = closeOnce(window)
            if result == .requested {
                return await confirmRequestedClose(for: window, originalResult: result)
            }

            if result != .temporarilyUnavailable {
                return result
            }
        }
        return .temporarilyUnavailable
    }

    /// AXPress 返回 success 只代表 macOS 收下了关闭请求，这里回读窗口是否真的没了。
    ///
    /// 回读不能只看 AX。Mac Catalyst App（例如 Shadowrocket）窗口关掉之后，
    /// 它的 AXUIElement 仍然可读，`isAlive` 会一直返回 true，关闭看起来永远没生效；
    /// CG 的当前 Space 窗口名单才是「窗口还在不在」的可信来源。
    private func confirmRequestedClose(
        for window: ManagedWindow,
        originalResult: WindowCloseResult
    ) async -> WindowCloseResult {
        let deadline = ContinuousClock.now.advanced(by: Self.closeConfirmationTimeout)
        while true {
            if isClosed(window) { return .windowUnavailable }
            guard ContinuousClock.now < deadline else { break }
            do {
                try await Task.sleep(for: Self.closeConfirmationPollInterval)
            } catch {
                break
            }
        }

        // 窗口还在，多半是弹出了保存或确认对话框：保留原始结果，Tab 等用户处理完再消失。
        return originalResult
    }

    private func closeOnce(_ window: ManagedWindow) -> WindowCloseResult {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            window.element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard roleResult == .success else {
            return WindowCloseResult.classify(
                actionError: roleResult,
                hasBlockingModalUI: false
            )
        }
        guard roleValue != nil else { return .windowUnavailable }

        let hasBlockingModalUI = hasBlockingModalUI(for: window)
        var value: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            window.element,
            kAXCloseButtonAttribute as CFString,
            &value
        )
        guard copyResult == .success else {
            return WindowCloseResult.classify(
                actionError: copyResult,
                hasBlockingModalUI: hasBlockingModalUI
            )
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return hasBlockingModalUI ? .blockedByModalDialog : .unsupported
        }

        let closeButton = value as! AXUIElement
        if AXHelpers.bool(kAXEnabledAttribute as CFString, of: closeButton) == false {
            return hasBlockingModalUI ? .blockedByModalDialog : .unsupported
        }

        let actionResult = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        return WindowCloseResult.classify(
            actionError: actionResult,
            hasBlockingModalUI: hasBlockingModalUI
        )
    }

    private func hasBlockingModalUI(for window: ManagedWindow) -> Bool {
        if let sheets = AXHelpers.attribute(
            "AXSheets" as CFString,
            of: window.element
        ) as? [AXUIElement], !sheets.isEmpty {
            return true
        }

        let applicationElement = AXUIElementCreateApplication(window.ownerPID)
        return AXHelpers.windows(of: applicationElement).contains { candidate in
            guard !CFEqual(candidate, window.element) else { return false }
            if AXHelpers.bool(kAXModalAttribute as CFString, of: candidate) == true {
                return true
            }
            let subrole = AXHelpers.string(kAXSubroleAttribute as CFString, of: candidate)
            return subrole == (kAXDialogSubrole as String)
                || subrole == (kAXSystemDialogSubrole as String)
        }
    }

    func isAlive(_ window: ManagedWindow) -> Bool {
        AXHelpers.string(kAXRoleAttribute as CFString, of: window.element) != nil
    }

    /// 窗口是否已经不存在：AX 元素失效，或者它已经从当前 Space 的窗口名单里消失。
    ///
    /// 切换桌面、窗口被拖到别的 Space 时同样会离开这份名单。所以调用方要么刚刚
    /// 对这个窗口发过关闭请求，要么先确认布局还停在当前桌面；日常巡检不能拿它
    /// 替代 `isAlive`，否则切一次桌面就会把所有 Tab 清掉。
    func isClosed(_ window: ManagedWindow) -> Bool {
        guard isAlive(window) else { return true }
        // 读不到窗口名单时不下结论，宁可保留 Tab。
        guard let onScreenWindowIDs = onScreenWindowIDs() else { return false }
        return isClosed(window, onScreenWindowIDs: onScreenWindowIDs)
    }

    /// 判断窗口是否已经关闭，复用一次性读好的屏幕窗口名单。
    func isClosed(_ window: ManagedWindow, onScreenWindowIDs: Set<CGWindowID>) -> Bool {
        let isElementAlive = isAlive(window)
        let isListedOnScreen = onScreenWindowIDs.contains(window.windowID)
        // 只有窗口确实离开名单时才值得再读一次 AX。
        let isMinimized = isElementAlive
            && !isListedOnScreen
            && AXHelpers.bool(kAXMinimizedAttribute as CFString, of: window.element) == true

        return WindowClosure.isClosed(
            accessibilityElementAlive: isElementAlive,
            isListedOnScreen: isListedOnScreen,
            isMinimized: isMinimized
        )
    }

    /// 当前 Space 上没有被最小化、也没有被隐藏的窗口 ID。
    ///
    /// 读不到名单时返回 nil，调用方应当放弃这一轮判断，而不是把窗口当成已关闭。
    func onScreenWindowIDs() -> Set<CGWindowID>? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return Set(
            rawWindowInfo.compactMap { info in
                (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            }
        )
    }

    /// 返回系统当前真正聚焦的受管窗口。
    ///
    /// 不能只比较前台 App 的 PID：同一个 App 可以同时拥有多个受管窗口，
    /// 例如 ChatGPT 的不同项目窗口。这里必须继续比较 AXFocusedWindow 的
    /// 窗口级身份，才能让 Tab 高亮跟随用户在系统中直接进行的窗口切换。
    func focusedManagedWindow(in windows: [ManagedWindow]) -> ManagedWindow? {
        guard
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            windows.contains(where: { $0.ownerPID == frontmostPID })
        else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(frontmostPID)
        let focusedElement = AXHelpers.attribute(
            kAXFocusedWindowAttribute as CFString,
            of: applicationElement
        ) ?? AXHelpers.attribute(
            kAXMainWindowAttribute as CFString,
            of: applicationElement
        )

        guard
            let focusedElement,
            CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedWindowElement = focusedElement as! AXUIElement
        if NativeFullScreen.isActive(
            element: focusedWindowElement,
            frame: AXHelpers.frame(of: focusedWindowElement),
            displays: NativeFullScreen.displayBounds()
        ) {
            return nil
        }

        // 前台 App 的窗口全关掉之后，AXFocusedWindow 可能仍然指向那个「关不掉的」
        // AX 元素（Mac Catalyst）。把已经离开屏幕名单的窗口排除，Tab 高亮才不会
        // 跳回一个已经不存在的窗口，后续重排也不会再去激活它。
        let listedIDs = onScreenWindowIDs()
        let candidates = windows.filter { window in
            window.ownerPID == frontmostPID
                && (listedIDs.map { $0.contains(window.windowID) } ?? true)
        }
        if let exact = candidates.first(where: { CFEqual($0.element, focusedWindowElement) }) {
            return exact
        }

        // 部分 App 每次读取 AXFocusedWindow 都会给出新的 AXUIElement，CFEqual 会失败。
        // 用当前 AX frame 对齐同一进程里的受管窗口。
        if let focusedFrame = AXHelpers.frame(of: focusedWindowElement) {
            let scored = candidates.compactMap { window -> (ManagedWindow, CGFloat)? in
                guard let frame = AXHelpers.frame(of: window.element) else { return nil }
                return (window, WindowIndexer.geometryDelta(frame, focusedFrame))
            }
            if let index = WindowFocusMatch.bestIndex(deltas: scored.map(\.1)) {
                return scored[index].0
            }
        }

        return candidates.count == 1 ? candidates[0] : nil
    }
}
