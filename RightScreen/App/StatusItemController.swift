import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: LayoutCoordinator
    private let onOpenHotKeySettings: () -> Void
    private let statusItem: NSStatusItem

    private lazy var layoutItems: [(kind: LayoutKind, item: NSMenuItem)] = LayoutKind.allCases.map { kind in
        let item = menuItem(
            title: "\(kind.menuTitle)（\(kind.menuSubtitle)）",
            action: #selector(startLayoutFromMenu(_:)),
            keyEquivalent: ""
        )
        item.image = LayoutKindIcon.image(for: kind)
        item.representedObject = kind.rawValue
        return (kind, item)
    }

    private lazy var bentoItem: NSMenuItem = {
        let item = menuItem(
            title: "网格",
            action: #selector(startBento),
            keyEquivalent: ""
        )
        item.image = LayoutKindIcon.bentoImage()
        return item
    }()

    private lazy var exitLayoutItem = menuItem(
        title: "退出当前布局",
        action: #selector(exitLayout),
        keyEquivalent: ""
    )
    private lazy var hotKeySettingsItem = menuItem(
        title: "快捷键设置…",
        action: #selector(openHotKeySettings),
        keyEquivalent: ""
    )
    private lazy var permissionItem = menuItem(
        title: "打开辅助功能权限设置…",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    private lazy var generateAppItem = menuItem(
        title: "生成并升级 app",
        action: #selector(generateApp),
        keyEquivalent: ""
    )

    init(coordinator: LayoutCoordinator, onOpenHotKeySettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onOpenHotKeySettings = onOpenHotKeySettings
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

        menu.addItem(.sectionHeader(title: "Tab Mode"))
        for entry in layoutItems {
            menu.addItem(entry.item)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Grid Mode"))
        menu.addItem(bentoItem)

        menu.addItem(.separator())
        menu.addItem(exitLayoutItem)
        menu.addItem(hotKeySettingsItem)
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
        for entry in layoutItems {
            entry.item.state = activeKind == entry.kind ? .on : .off
        }
        bentoItem.state = coordinator.isBentoActive ? .on : .off
        exitLayoutItem.isEnabled = coordinator.hasActiveLayout
        permissionItem.state = Permissions.isAccessibilityGranted ? .on : .off
    }

    @objc private func startLayoutFromMenu(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let kind = LayoutKind(rawValue: rawValue)
        else {
            return
        }
        coordinator.startLayout(kind)
    }

    @objc private func startBento() {
        coordinator.startBento()
    }

    @objc private func exitLayout() {
        coordinator.exitLayout()
    }

    @objc private func openHotKeySettings() {
        onOpenHotKeySettings()
    }

    @objc private func openAccessibilitySettings() {
        if let issue = Permissions.signingIssue {
            showSigningIssue(issue)
            return
        }

        if Permissions.isAccessibilityGranted {
            Permissions.openAccessibilitySettings(promptIfNeeded: false)
            return
        }

        Permissions.openAccessibilitySettings(promptIfNeeded: true)
    }

    private func showSigningIssue(_ issue: String) {
        let help = Permissions.accessibilityHelpMessage(signingIssue: issue)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = help.title
        alert.informativeText = help.message
        alert.addButton(withTitle: "好")
        alert.runModal()
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
