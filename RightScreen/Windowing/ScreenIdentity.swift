import AppKit
import CoreGraphics

enum ScreenIdentity {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        guard id != 0 else { return nil }
        return NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// AX / CGWindowList 的 Y=0 是菜单栏所在屏的顶边，必须用 `screens[0]`，
    /// 不能用布局目标屏或 `NSScreen.main`。插拔显示器后主屏会换，更不能缓存。
    static var primaryFrame: CGRect {
        NSScreen.screens.first?.frame ?? .zero
    }

    static func convertFrame(_ frame: CGRect) -> CGRect {
        ScreenFrameConversion.flippingY(frame, relativeTo: primaryFrame)
    }

    /// 窗口相交面积最大的那块屏；都没有相交时返回 nil。
    static func preferredScreenIndex(screenFrames: [CGRect], windowFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty, !windowFrames.isEmpty else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screenFrame) in screenFrames.enumerated() {
            let area = windowFrames.reduce(CGFloat(0)) { sum, windowFrame in
                let intersection = windowFrame.intersection(screenFrame)
                guard !intersection.isNull, !intersection.isInfinite else { return sum }
                return sum + intersection.width * intersection.height
            }
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestArea > 0 ? bestIndex : nil
    }
}
