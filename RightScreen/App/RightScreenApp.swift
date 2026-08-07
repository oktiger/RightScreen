import AppKit

@main
@MainActor
enum RightScreenApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()

        withExtendedLifetime(delegate) {}
    }
}
