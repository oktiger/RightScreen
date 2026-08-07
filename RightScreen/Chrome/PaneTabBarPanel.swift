import AppKit

@MainActor
private final class PaneTabItemView: NSView {
    private let selectButton = NSButton()
    private let closeButton = NSButton()
    private let selectionHandler: () -> Void
    private let closeHandler: () -> Void

    init(
        title: String,
        isSelected: Bool,
        selectionHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void
    ) {
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        updateSelection(isSelected)

        selectButton.title = title
        selectButton.toolTip = title
        selectButton.isBordered = false
        selectButton.alignment = .left
        selectButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        selectButton.cell?.lineBreakMode = .byTruncatingTail
        selectButton.target = self
        selectButton.action = #selector(selectTab)

        closeButton.title = "×"
        closeButton.toolTip = "关闭窗口"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        addSubview(selectButton)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let closeWidth: CGFloat = 26
        selectButton.frame = CGRect(x: 8, y: 0, width: max(0, bounds.width - closeWidth - 8), height: bounds.height)
        closeButton.frame = CGRect(x: bounds.width - closeWidth, y: 0, width: closeWidth, height: bounds.height)
    }

    @objc private func selectTab() {
        selectionHandler()
    }

    @objc private func closeWindow() {
        closeHandler()
    }

    func updateSelection(_ isSelected: Bool) {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }
}

@MainActor
final class PaneTabBarPanel: NSPanel {
    private static let horizontalInset: CGFloat = 6
    private static let minimumTabWidth: CGFloat = 112
    private static let maximumTabWidth: CGFloat = 180

    private let selectionHandler: (Int) -> Void
    private let closeHandler: (Int) -> Void
    private let availableFrame: CGRect
    private let tabWidth: CGFloat
    private let scrollView = NSScrollView()
    private let tabStripView = NSView()
    private var tabItemViews: [PaneTabItemView] = []
    private var titles: [String]
    private var selectedIndex: Int

    init(
        frame: CGRect,
        screenWidth: CGFloat,
        titles: [String],
        selectionHandler: @escaping (Int) -> Void,
        closeHandler: @escaping (Int) -> Void
    ) {
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        availableFrame = frame
        tabWidth = min(
            Self.maximumTabWidth,
            max(Self.minimumTabWidth, floor(screenWidth / 8))
        )
        self.titles = titles
        selectedIndex = titles.isEmpty ? -1 : 0

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
        hasShadow = true
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
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
        for (index, title) in titles.enumerated() {
            let item = PaneTabItemView(
                title: title,
                isSelected: index == selectedIndex,
                selectionHandler: { [weak self] in self?.selectionHandler(index) },
                closeHandler: { [weak self] in self?.closeHandler(index) }
            )
            item.frame = CGRect(
                x: CGFloat(index) * tabWidth,
                y: 0,
                width: tabWidth,
                height: itemHeight
            )
            tabStripView.addSubview(item)
            tabItemViews.append(item)
        }

        let stripWidth = CGFloat(titles.count) * tabWidth
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

        if titles.indices.contains(selectedIndex) {
            tabStripView.scrollToVisible(
                CGRect(
                    x: CGFloat(selectedIndex) * tabWidth,
                    y: 0,
                    width: tabWidth,
                    height: itemHeight
                )
            )
        }
    }

    func updateTitles(_ titles: [String], selectedIndex: Int) {
        let titlesChanged = self.titles != titles
        self.titles = titles
        self.selectedIndex = titles.indices.contains(selectedIndex) ? selectedIndex : -1
        if titlesChanged || tabItemViews.count != titles.count {
            rebuildTabs()
            return
        }

        for (index, item) in tabItemViews.enumerated() {
            item.updateSelection(index == self.selectedIndex)
        }

        if titles.indices.contains(self.selectedIndex) {
            tabStripView.scrollToVisible(
                CGRect(
                    x: CGFloat(self.selectedIndex) * tabWidth,
                    y: 0,
                    width: tabWidth,
                    height: max(0, availableFrame.height - 8)
                )
            )
        }
    }
}
