import AppKit

struct PaneTabPresentation: Equatable {
    let title: String
    let ownerPID: pid_t

    var applicationIcon: NSImage? {
        guard let icon = NSRunningApplication(processIdentifier: ownerPID)?.icon else {
            return nil
        }
        let scaledIcon = (icon.copy() as? NSImage) ?? icon
        scaledIcon.size = CGSize(width: 13, height: 13)
        return scaledIcon
    }
}

@MainActor
private final class PaneTabItemView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 8
        static let titleLeadingInset: CGFloat = 9
        static let closeButtonWidth: CGFloat = 23
    }

    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let selectButton = NSButton()
    private let closeButton = NSButton()
    private let selectionHandler: () -> Void
    private let closeHandler: () -> Void

    init(
        tab: PaneTabPresentation,
        isSelected: Bool,
        selectionHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void
    ) {
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        super.init(frame: .zero)

        wantsLayer = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = Metrics.cornerRadius
        materialView.layer?.masksToBounds = true

        tintView.wantsLayer = true
        tintView.layer?.cornerRadius = Metrics.cornerRadius
        tintView.layer?.masksToBounds = true

        selectButton.title = tab.title
        selectButton.toolTip = tab.title
        selectButton.image = tab.applicationIcon
        selectButton.imagePosition = tab.applicationIcon == nil ? .noImage : .imageLeading
        selectButton.imageScaling = .scaleProportionallyDown
        selectButton.imageHugsTitle = true
        selectButton.isBordered = false
        selectButton.alignment = .left
        selectButton.font = .systemFont(ofSize: 11, weight: .medium)
        selectButton.cell?.lineBreakMode = .byTruncatingTail
        selectButton.target = self
        selectButton.action = #selector(selectTab)

        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "关闭窗口"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        closeButton.toolTip = "关闭窗口"
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        addSubview(materialView)
        addSubview(tintView)
        addSubview(selectButton)
        addSubview(closeButton)
        updateSelection(isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds
        selectButton.frame = CGRect(
            x: Metrics.titleLeadingInset,
            y: 0,
            width: max(0, bounds.width - Metrics.closeButtonWidth - Metrics.titleLeadingInset),
            height: bounds.height
        )
        closeButton.frame = CGRect(
            x: bounds.width - Metrics.closeButtonWidth,
            y: 0,
            width: Metrics.closeButtonWidth,
            height: bounds.height
        )
    }

    @objc private func selectTab() {
        selectionHandler()
    }

    @objc private func closeWindow() {
        closeHandler()
    }

    func updateSelection(_ isSelected: Bool) {
        // Keep every item independently frosted. The selected item receives an
        // almost opaque white tint, matching the reference while preserving a
        // trace of the material beneath it.
        tintView.layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.97).cgColor
            : NSColor.white.withAlphaComponent(0.13).cgColor

        selectButton.contentTintColor = isSelected
            ? NSColor.black.withAlphaComponent(0.92)
            : NSColor.white.withAlphaComponent(0.94)
        closeButton.contentTintColor = isSelected
            ? NSColor.black.withAlphaComponent(0.48)
            : NSColor.white.withAlphaComponent(0.78)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isSelected ? 0.16 : 0.08
        layer?.shadowRadius = isSelected ? 2 : 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
}

@MainActor
final class PaneTabBarPanel: NSPanel {
    private static let horizontalInset: CGFloat = 6
    private static let tabWidth: CGFloat = 154
    private static let tabSpacing: CGFloat = 4

    private let selectionHandler: (Int) -> Void
    private let closeHandler: (Int) -> Void
    private let availableFrame: CGRect
    private let scrollView = NSScrollView()
    private let tabStripView = NSView()
    private var tabItemViews: [PaneTabItemView] = []
    private var tabs: [PaneTabPresentation]
    private var selectedIndex: Int

    init(
        frame: CGRect,
        tabs: [PaneTabPresentation],
        selectionHandler: @escaping (Int) -> Void,
        closeHandler: @escaping (Int) -> Void
    ) {
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        availableFrame = frame
        self.tabs = tabs
        selectedIndex = tabs.isEmpty ? -1 : 0

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        configureTabStrip()
        rebuildTabs()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func configurePanel() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        collectionBehavior = [.ignoresCycle]
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func configureTabStrip() {
        guard let contentView else { return }
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tabStripView
        contentView.addSubview(scrollView)
    }

    private func rebuildTabs() {
        tabStripView.subviews.forEach { $0.removeFromSuperview() }
        tabItemViews.removeAll(keepingCapacity: true)

        let itemHeight = max(0, availableFrame.height - 8)
        for (index, tab) in tabs.enumerated() {
            let item = PaneTabItemView(
                tab: tab,
                isSelected: index == selectedIndex,
                selectionHandler: { [weak self] in self?.selectionHandler(index) },
                closeHandler: { [weak self] in self?.closeHandler(index) }
            )
            item.frame = CGRect(
                x: CGFloat(index) * (Self.tabWidth + Self.tabSpacing),
                y: 0,
                width: Self.tabWidth,
                height: itemHeight
            )
            tabStripView.addSubview(item)
            tabItemViews.append(item)
        }

        let stripWidth = CGFloat(tabs.count) * Self.tabWidth
            + CGFloat(max(0, tabs.count - 1)) * Self.tabSpacing
        let panelWidth = min(
            availableFrame.width,
            stripWidth + Self.horizontalInset * 2
        )
        setFrame(
            CGRect(
                x: availableFrame.minX,
                y: availableFrame.minY,
                width: panelWidth,
                height: availableFrame.height
            ),
            display: true
        )
        scrollView.frame = contentView?.bounds.insetBy(dx: Self.horizontalInset, dy: 4) ?? .zero
        scrollView.hasHorizontalScroller = stripWidth > scrollView.bounds.width
        tabStripView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(stripWidth, scrollView.bounds.width), height: itemHeight)
        )

        if tabs.indices.contains(selectedIndex) {
            tabStripView.scrollToVisible(
                CGRect(
                    x: CGFloat(selectedIndex) * (Self.tabWidth + Self.tabSpacing),
                    y: 0,
                    width: Self.tabWidth,
                    height: itemHeight
                )
            )
        }
    }

    func updateTabs(_ tabs: [PaneTabPresentation], selectedIndex: Int) {
        let tabsChanged = self.tabs != tabs
        self.tabs = tabs
        self.selectedIndex = tabs.indices.contains(selectedIndex) ? selectedIndex : -1
        if tabsChanged || tabItemViews.count != tabs.count {
            rebuildTabs()
            return
        }

        for (index, item) in tabItemViews.enumerated() {
            item.updateSelection(index == self.selectedIndex)
        }

        if tabs.indices.contains(self.selectedIndex) {
            tabStripView.scrollToVisible(
                CGRect(
                    x: CGFloat(self.selectedIndex) * (Self.tabWidth + Self.tabSpacing),
                    y: 0,
                    width: Self.tabWidth,
                    height: max(0, availableFrame.height - 8)
                )
            )
        }
    }
}
