import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var layoutCoordinator: LayoutCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = LayoutCoordinator()
        layoutCoordinator = coordinator
        statusItemController = StatusItemController(coordinator: coordinator)
    }

    func applicationWillTerminate(_ notification: Notification) {
        layoutCoordinator?.exitLayout()
    }
}
