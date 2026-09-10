import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: LayoutCoordinator
    private let onOpenHotKeySettings: () -> Void
    private var statusItem: NSStatusItem
    private var presenceWatchTask: Task<Void, Never>?
    private var didOfferMenuBarSettings = false

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

    init(coordinator: LayoutCoordinator, onOpenHotKeySettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onOpenHotKeySettings = onOpenHotKeySettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        watchPresence()
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = LayoutKindIcon.statusBarImage()
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "RightScreen"
            button.setAccessibilityLabel("RightScreen")
            if button.image == nil {
                button.title = "RS"
                button.imagePosition = .imageLeading
            }
        }
        applyMenu()
    }

    private func applyMenu() {
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
        menu.addItem(menuItem(title: "退出 RightScreen", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func watchPresence() {
        presenceWatchTask?.cancel()
        presenceWatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            if self.isParkedOffMenuBar() {
                self.recreateStatusItem()
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
            if self.isParkedOffMenuBar() {
                self.offerMenuBarSettingsIfNeeded()
            }
        }
    }

    private func recreateStatusItem() {
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItem()
    }

    private func isParkedOffMenuBar() -> Bool {
        if !statusItem.isVisible {
            return true
        }
        guard let window = statusItem.button?.window else {
            return false
        }
        return StatusItemPresence.isParkedOffMenuBar(windowFrame: window.frame)
    }

    private func offerMenuBarSettingsIfNeeded() {
        guard !didOfferMenuBarSettings else { return }
        didOfferMenuBarSettings = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "菜单栏图标被系统隐藏"
        alert.informativeText = """
        RightScreen 正在运行，但 macOS 可能未允许它显示在菜单栏。

        请打开“系统设置 → 菜单栏”，在“允许在菜单栏中显示”中打开 RightScreen。
        """
        alert.addButton(withTitle: "打开菜单栏设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openMenuBarSettings()
        }
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

    @objc private func quit() {
        coordinator.exitLayout()
        NSApplication.shared.terminate(nil)
    }
}
