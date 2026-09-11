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
    private static let closeVerificationDelay: Duration = .milliseconds(160)

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

    func frameMatches(_ window: ManagedWindow, accessibilityFrame expected: CGRect) -> Bool {
        guard let actual = AXHelpers.frame(of: window.element) else { return false }
        return PaneFrameFit.matches(actual, expected: expected)
    }

    @discardableResult
    func setAppKitFrame(_ frame: CGRect, for window: ManagedWindow) -> Bool {
        setAccessibilityFrame(ScreenIdentity.convertFrame(frame), for: window)
    }

    @discardableResult
    func raise(_ window: ManagedWindow) -> Bool {
        guard isAlive(window) else { return false }
        guard !isNativeFullScreen(window) else { return false }

        let ordered = orderFrontWithinApplication(window)

        // `NSRunningApplication.activate()` and `kAXFrontmostAttribute` bring every
        // window of that process forward. Chrome then covers the other pane.
        // Activate with "front window only" after this window is already the app's
        // front window, so siblings stay where they were.
        let activated = ProcessActivation.bringFrontWindowOnly(pid: window.ownerPID)

        return ordered || activated
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
                return await verifyRequestedCloseAndApplyCompatibilityFallback(
                    for: window,
                    originalResult: result
                )
            }

            if let compatibilityResult = closeUsingCompatibilityFallback(for: window) {
                return compatibilityResult
            }

            if result != .temporarilyUnavailable {
                return result
            }
        }
        return .temporarilyUnavailable
    }

    /// 一些 Mac Catalyst App 会对 AXCloseButton 的 AXPress 返回 success，却不执行关闭。
    /// 仅对经过验证的 bundle 在窗口仍然存活时转用其 App 菜单中的关闭命令。
    private func verifyRequestedCloseAndApplyCompatibilityFallback(
        for window: ManagedWindow,
        originalResult: WindowCloseResult
    ) async -> WindowCloseResult {
        guard WindowCloseCompatibility.strategy(for: window.bundleIdentifier) != nil else {
            return originalResult
        }

        do {
            try await Task.sleep(for: Self.closeVerificationDelay)
        } catch {
            return originalResult
        }

        guard isAlive(window), !hasBlockingModalUI(for: window) else {
            return originalResult
        }

        return closeUsingCompatibilityFallback(for: window)
            ?? originalResult
    }

    /// 返回 nil 代表没有适用的兼容策略，调用方应保留原始 AX 结果。
    private func closeUsingCompatibilityFallback(for window: ManagedWindow) -> WindowCloseResult? {
        guard let strategy = WindowCloseCompatibility.strategy(for: window.bundleIdentifier) else {
            return nil
        }

        switch strategy {
        case .menuCloseCommand:
            guard let closeMenuItem = closeMenuItem(for: window) else {
                return nil
            }
            let result = AXUIElementPerformAction(closeMenuItem, kAXPressAction as CFString)
            return WindowCloseResult.classify(
                actionError: result,
                hasBlockingModalUI: hasBlockingModalUI(for: window)
            )
        }
    }

    /// 不依赖本地化标题（例如“Close”/“关闭”），只匹配 AppKit/Catalyst 的标准 action。
    private func closeMenuItem(for window: ManagedWindow) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(window.ownerPID)
        guard let menuBarValue = AXHelpers.attribute(
            kAXMenuBarAttribute as CFString,
            of: applicationElement
        ), CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let menuBar = menuBarValue as! AXUIElement
        for menuBarItem in AXHelpers.children(of: menuBar) {
            for menu in AXHelpers.children(of: menuBarItem) {
                if let closeItem = AXHelpers.children(of: menu).first(where: {
                    AXHelpers.string(kAXIdentifierAttribute as CFString, of: $0) == "performClose:"
                }) {
                    return closeItem
                }
            }
        }
        return nil
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

        let candidates = windows.filter { $0.ownerPID == frontmostPID }
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
