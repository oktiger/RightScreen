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

    var tabTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? appName : trimmedTitle
    }
}
