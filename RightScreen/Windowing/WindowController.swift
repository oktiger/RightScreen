import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowController {
    @discardableResult
    func setAccessibilityFrame(_ frame: CGRect, for window: ManagedWindow) -> Bool {
        guard isAlive(window) else { return false }

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

    @discardableResult
    func setAppKitFrame(_ frame: CGRect, on screen: NSScreen, for window: ManagedWindow) -> Bool {
        setAccessibilityFrame(accessibilityFrame(from: frame, mainScreen: screen), for: window)
    }

    @discardableResult
    func raise(_ window: ManagedWindow) -> Bool {
        guard isAlive(window) else { return false }

        // AXRaise alone only changes the order inside some applications. When the
        // target belongs to an inactive app, its window can remain behind the
        // currently active app even though AX reports success.
        let runningApplication = NSRunningApplication(processIdentifier: window.ownerPID)
        if runningApplication?.isActive != true {
            _ = runningApplication?.activate()
        }

        let applicationElement = AXUIElementCreateApplication(window.ownerPID)
        let frontmostResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
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
            || (frontmostResult == .success
                && (focusedWindowResult == .success || mainWindowResult == .success))
    }

    @discardableResult
    func close(_ window: ManagedWindow) -> Bool {
        guard
            isAlive(window),
            let value = AXHelpers.attribute(kAXCloseButtonAttribute as CFString, of: window.element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return false
        }

        let closeButton = value as! AXUIElement
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    func isAlive(_ window: ManagedWindow) -> Bool {
        AXHelpers.string(kAXRoleAttribute as CFString, of: window.element) != nil
    }

    private func accessibilityFrame(from appKitFrame: CGRect, mainScreen: NSScreen) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: mainScreen.frame.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
