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
        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWindowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if isGoogleChrome, !trimmedAppName.isEmpty, !trimmedWindowTitle.isEmpty {
            return "\(trimmedAppName)：\(trimmedWindowTitle)"
        }

        if !trimmedAppName.isEmpty {
            return trimmedAppName
        }

        return trimmedWindowTitle
    }

    private var isGoogleChrome: Bool {
        bundleIdentifier?.lowercased().hasPrefix("com.google.chrome") == true
    }
}
