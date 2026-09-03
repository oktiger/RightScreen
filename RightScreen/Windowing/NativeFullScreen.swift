import ApplicationServices
import CoreGraphics

enum NativeFullScreen {
    /// 相对整块屏幕（含菜单栏）的覆盖率。普通最大化只铺 visibleFrame，会明显低于此值。
    static let coverageRatio: CGFloat = 0.96

    /// AX / CG 坐标系下的当前显示器 bounds。
    static func displayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return []
        }

        return displays.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
    }

    static func isActive(element: AXUIElement, frame: CGRect?, displays: [CGRect]) -> Bool {
        if AXHelpers.bool("AXFullScreen" as CFString, of: element) == true {
            return true
        }
        guard let frame else { return false }
        return coversDisplay(frame, displays: displays)
    }

    /// 窗口几乎铺满某一块物理屏时，视为正在进入或已处于原生全屏。
    static func coversDisplay(_ axFrame: CGRect, displays: [CGRect]) -> Bool {
        let frameArea = axFrame.width * axFrame.height
        guard frameArea > 0 else { return false }

        return displays.contains { display in
            let displayArea = display.width * display.height
            guard displayArea > 0 else { return false }

            let intersection = axFrame.intersection(display)
            guard !intersection.isNull, !intersection.isInfinite else { return false }

            let coverage = (intersection.width * intersection.height) / displayArea
            let sizeRatio = min(frameArea, displayArea) / max(frameArea, displayArea)
            return coverage >= coverageRatio && sizeRatio >= coverageRatio
        }
    }
}
