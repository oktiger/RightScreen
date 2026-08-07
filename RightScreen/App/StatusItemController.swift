import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: LayoutCoordinator
    private let statusItem: NSStatusItem

    private lazy var split2Item = menuItem(
        title: "左右二分",
        action: #selector(startSplit2),
        keyEquivalent: ""
    )
    private lazy var split4Item = menuItem(
        title: "四等分",
        action: #selector(startSplit4),
        keyEquivalent: ""
    )
    private lazy var exitLayoutItem = menuItem(
        title: "退出当前布局",
        action: #selector(exitLayout),
        keyEquivalent: ""
    )
    private lazy var permissionItem = menuItem(
        title: "打开辅助功能权限设置…",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    private lazy var generateAppItem = menuItem(
        title: "生成 app",
        action: #selector(generateApp),
        keyEquivalent: ""
    )

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.2x1",
                accessibilityDescription: "RightScreen"
            )
            button.toolTip = "RightScreen"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(split2Item)
        menu.addItem(split4Item)
        menu.addItem(.separator())
        menu.addItem(exitLayoutItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(generateAppItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "退出 RightScreen", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        let activeKind = coordinator.session?.kind
        split2Item.state = activeKind == .split2 ? .on : .off
        split4Item.state = activeKind == .split4 ? .on : .off
        exitLayoutItem.isEnabled = coordinator.hasActiveLayout
        permissionItem.state = Permissions.isAccessibilityGranted ? .on : .off
    }

    @objc private func startSplit2() {
        coordinator.startLayout(.split2)
    }

    @objc private func startSplit4() {
        coordinator.startLayout(.split4)
    }

    @objc private func exitLayout() {
        coordinator.exitLayout()
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func generateApp() {
        coordinator.exitLayout()
        BuildAndRestartService.start()
    }

    @objc private func quit() {
        coordinator.exitLayout()
        NSApplication.shared.terminate(nil)
    }
}
