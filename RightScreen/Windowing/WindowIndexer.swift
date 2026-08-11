import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowIndexer {
    private struct CGWindowRecord {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let title: String
        let frame: CGRect
    }

    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine"
    ]

    private let excludedOwnerNames: Set<String> = [
        "Dock",
        "Window Server",
        "SystemUIServer",
        "Control Center",
        "Notification Center",
        "Wallpaper",
        "屏幕保护程序"
    ]

    /// `.optionOnScreenOnly` 是公开 API 中限定当前活动 Space 的关键过滤条件。
    /// CG 提供当前 Space 的稳定前后顺序，AX 再通过 PID、标题和 frame 映射到可操作窗口。
    func currentSpaceWindows() -> [ManagedWindow] {
        currentSpaceWindows(ownerPID: nil)
    }

    /// AX 窗口事件到达后仅映射对应进程，避免为一个新窗口重新读取所有 App 的 AX 窗口。
    func currentSpaceWindows(ownerPID: pid_t) -> [ManagedWindow] {
        currentSpaceWindows(ownerPID: Optional(ownerPID))
    }

    private func currentSpaceWindows(ownerPID: pid_t?) -> [ManagedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let records = rawWindowInfo.compactMap(makeRecord).filter { record in
            ownerPID == nil || record.ownerPID == ownerPID
        }
        var axWindowsByPID: [pid_t: [AXUIElement]] = [:]
        var usedIndicesByPID: [pid_t: Set<Int>] = [:]
        var result: [ManagedWindow] = []

        for record in records {
            guard let runningApp = NSRunningApplication(processIdentifier: record.ownerPID) else { continue }

            let axWindows: [AXUIElement]
            if let cached = axWindowsByPID[record.ownerPID] {
                axWindows = cached
            } else {
                let appElement = AXUIElementCreateApplication(record.ownerPID)
                let eligible = AXHelpers.windows(of: appElement).filter(isEligibleAXWindow)
                axWindowsByPID[record.ownerPID] = eligible
                axWindows = eligible
            }

            let usedIndices = usedIndicesByPID[record.ownerPID, default: []]
            guard let matchIndex = bestMatch(for: record, in: axWindows, excluding: usedIndices) else {
                continue
            }

            let element = axWindows[matchIndex]
            guard let axFrame = AXHelpers.frame(of: element) else { continue }
            usedIndicesByPID[record.ownerPID, default: []].insert(matchIndex)

            let axTitle = AXHelpers.string(kAXTitleAttribute as CFString, of: element) ?? record.title
            result.append(
                ManagedWindow(
                    windowID: record.windowID,
                    ownerPID: record.ownerPID,
                    bundleIdentifier: runningApp.bundleIdentifier,
                    appName: runningApp.localizedName ?? "应用",
                    title: axTitle,
                    frame: axFrame,
                    element: element
                )
            )
        }

        return result
    }

    private func makeRecord(from info: [String: Any]) -> CGWindowRecord? {
        guard
            let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
            let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
            layerNumber.intValue == 0,
            let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else {
            return nil
        }

        let ownerPID = pid_t(ownerPIDNumber.int32Value)
        guard ownerPID != getpid(), bounds.width >= 120, bounds.height >= 80 else { return nil }

        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else { return nil }

        let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
        guard !excludedOwnerNames.contains(ownerName) else { return nil }

        guard let runningApp = NSRunningApplication(processIdentifier: ownerPID) else { return nil }
        guard runningApp != .current else { return nil }
        guard runningApp.activationPolicy == .regular else { return nil }
        if let bundleIdentifier = runningApp.bundleIdentifier,
           excludedBundleIdentifiers.contains(bundleIdentifier) {
            return nil
        }

        return CGWindowRecord(
            windowID: CGWindowID(windowIDNumber.uint32Value),
            ownerPID: ownerPID,
            title: info[kCGWindowName as String] as? String ?? "",
            frame: bounds
        )
    }

    private func isEligibleAXWindow(_ element: AXUIElement) -> Bool {
        let role = AXHelpers.string(kAXRoleAttribute as CFString, of: element)
        let subrole = AXHelpers.string(kAXSubroleAttribute as CFString, of: element)
        guard role == (kAXWindowRole as String) else { return false }

        // A transient surface can be exposed as AXWindow even though it is not an
        // independently manageable document window. Prefer positive identification
        // of a standard window and fail closed for known non-document subroles.
        let excludedSubroles: Set<String> = [
            kAXDialogSubrole as String,
            kAXSystemDialogSubrole as String,
            kAXFloatingWindowSubrole as String,
            kAXSystemFloatingWindowSubrole as String
        ]
        if let subrole, excludedSubroles.contains(subrole) { return false }
        if let subrole, subrole != (kAXStandardWindowSubrole as String) { return false }

        guard AXHelpers.bool(kAXModalAttribute as CFString, of: element) != true else { return false }
        guard AXHelpers.bool(kAXMinimizedAttribute as CFString, of: element) != true else { return false }
        guard AXHelpers.bool("AXFullScreen" as CFString, of: element) != true else { return false }

        // Chrome/Finder can briefly omit AXSubrole while creating a real window.
        // In that ambiguous case, require the capabilities of an independent window;
        // popovers such as WeChat contact cards normally expose none of these controls.
        if subrole == nil {
            guard
                AXHelpers.isSettable(kAXPositionAttribute as CFString, of: element),
                AXHelpers.isSettable(kAXSizeAttribute as CFString, of: element),
                hasStandardWindowControl(element)
            else {
                return false
            }
        }

        // AXUIElementIsAttributeSettable can transiently return cannotComplete for Chrome
        // and Finder. The controller remains the single place that attempts the mutation.
        return AXHelpers.frame(of: element) != nil
    }

    private func hasStandardWindowControl(_ element: AXUIElement) -> Bool {
        AXHelpers.attribute(kAXCloseButtonAttribute as CFString, of: element) != nil
            || AXHelpers.attribute(kAXMinimizeButtonAttribute as CFString, of: element) != nil
            || AXHelpers.attribute(kAXZoomButtonAttribute as CFString, of: element) != nil
    }

    private func bestMatch(
        for record: CGWindowRecord,
        in windows: [AXUIElement],
        excluding usedIndices: Set<Int>
    ) -> Int? {
        let candidates = windows.indices.compactMap { index -> (index: Int, score: CGFloat)? in
            guard !usedIndices.contains(index), let frame = AXHelpers.frame(of: windows[index]) else {
                return nil
            }

            let geometryDelta = Self.geometryDelta(frame, record.frame)
            let title = AXHelpers.string(kAXTitleAttribute as CFString, of: windows[index]) ?? ""
            let titleMatches = !record.title.isEmpty && title == record.title
            let overlap = Self.overlapRatio(frame, record.frame)
            let sizeSimilarity = Self.sizeSimilarity(frame, record.frame)

            // A popup fully contained by its parent used to have an overlap ratio of
            // 1.0 because overlap was divided by the smaller area. Requiring similar
            // dimensions and using IoU prevents that popup CG record from stealing
            // the parent's AX element. A matching title only affects ranking; it is
            // not strong enough to bypass geometry validation.
            guard sizeSimilarity >= 0.72 else { return nil }
            guard geometryDelta <= 240 || overlap >= 0.65 else { return nil }
            return (index, geometryDelta - (titleMatches ? 1_000 : 0))
        }

        return candidates.min(by: { $0.score < $1.score })?.index
    }

    nonisolated static func geometryDelta(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    nonisolated static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let lhsArea = lhs.width * lhs.height
        let rhsArea = rhs.width * rhs.height
        guard lhsArea > 0, rhsArea > 0 else { return 0 }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhsArea + rhsArea - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    nonisolated static func sizeSimilarity(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return 0 }
        let widthRatio = min(lhs.width, rhs.width) / max(lhs.width, rhs.width)
        let heightRatio = min(lhs.height, rhs.height) / max(lhs.height, rhs.height)
        return min(widthRatio, heightRatio)
    }
}
