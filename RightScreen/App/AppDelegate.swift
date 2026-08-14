import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var layoutCoordinator: LayoutCoordinator?
    private var hotKeyCenter: HotKeyCenter?
    private var hotKeySettingsStore: HotKeySettingsStore?
    private var hotKeySettingsWindowController: HotKeySettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = LayoutCoordinator()
        layoutCoordinator = coordinator

        let store = HotKeySettingsStore()
        hotKeySettingsStore = store

        let hotKeys = HotKeyCenter()
        hotKeyCenter = hotKeys
        hotKeys.setHandler { [weak coordinator] action in
            guard let coordinator else { return }
            if let direction = action.paneMoveDirection {
                coordinator.moveFocusedTab(direction)
            } else if action == .fullScreen {
                coordinator.startLayout(.fullScreen)
            }
        }
        hotKeys.updateBindings(store.bindings)
        store.onChange = { [weak hotKeys] bindings in
            hotKeys?.updateBindings(bindings)
        }

        let settings = HotKeySettingsWindowController(store: store, hotKeyCenter: hotKeys)
        hotKeySettingsWindowController = settings

        statusItemController = StatusItemController(
            coordinator: coordinator,
            onOpenHotKeySettings: { [weak settings] in
                settings?.show()
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        layoutCoordinator?.exitLayout()
        hotKeyCenter?.invalidate()
    }
}
