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

    func moveOffscreen(_ window: ManagedWindow, relativeTo screen: NSScreen) {
        guard let currentFrame = AXHelpers.frame(of: window.element) else { return }
        let screenFrame = accessibilityFrame(from: screen.frame, mainScreen: screen)
        let hiddenFrame = CGRect(
            x: screenFrame.maxX + 120,
            y: currentFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )
        _ = setAccessibilityFrame(hiddenFrame, for: window)
    }

    func raise(_ window: ManagedWindow) {
        guard isAlive(window) else { return }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
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
