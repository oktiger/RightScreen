import ApplicationServices
import CoreGraphics

struct ManagedWindow {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    let frame: CGRect
    let element: AXUIElement

    func refersToSameAccessibilityWindow(as other: ManagedWindow) -> Bool {
        ownerPID == other.ownerPID && CFEqual(element, other.element)
    }

    var tabTitle: String {
        let trimmedWindowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWindowTitle.isEmpty {
            return trimmedWindowTitle
        }

        return appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
