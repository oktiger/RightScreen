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

/// Compact chrome control for tab actions (move / close).
/// Soft rounded hover fill + stronger pressed fill, matching common browser /
/// IDE tab affordances without changing the hit-target size.
@MainActor
private final class PaneTabChromeButton: NSControl {
    enum Style {
        case neutral
        case destructive
    }

    private enum Metrics {
        static let glyphSize: CGFloat = 16
        static let cornerRadius: CGFloat = 5
    }

    private let style: Style
    private let hoverBackground = NSView()
    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isPressed = false
    private var isOnSelectedTab = false
    private var idleTint = NSColor.white.withAlphaComponent(0.78)

    init(
        systemSymbolName: String,
        accessibilityDescription: String,
        pointSize: CGFloat,
        style: Style
    ) {
        self.style = style
        super.init(frame: .zero)

        wantsLayer = true
        focusRingType = .none
        toolTip = accessibilityDescription
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityDescription)

        hoverBackground.wantsLayer = true
        hoverBackground.layer?.cornerRadius = Metrics.cornerRadius
        hoverBackground.layer?.masksToBounds = true
        hoverBackground.isHidden = true

        imageView.image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = idleTint

        addSubview(hoverBackground)
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let side = min(Metrics.glyphSize, min(bounds.width, bounds.height) - 2)
        hoverBackground.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        hoverBackground.layer?.cornerRadius = min(Metrics.cornerRadius, side / 2)
        imageView.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        isPressed = false
        refreshAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        refreshAppearance()

        var keepTracking = true
        while keepTracking {
            guard let next = window?.nextEvent(
                matching: [.leftMouseUp, .leftMouseDragged]
            ) else {
                break
            }
            switch next.type {
            case .leftMouseDragged:
                let inside = bounds.contains(convert(next.locationInWindow, from: nil))
                if isPressed != inside {
                    isPressed = inside
                    refreshAppearance()
                }
            case .leftMouseUp:
                let inside = bounds.contains(convert(next.locationInWindow, from: nil))
                isPressed = false
                refreshAppearance()
                if inside {
                    sendAction(action, to: target)
                }
                keepTracking = false
            default:
                keepTracking = false
            }
        }
    }

    func updateChrome(isOnSelectedTab: Bool, idleTint: NSColor) {
        self.isOnSelectedTab = isOnSelectedTab
        self.idleTint = idleTint
        refreshAppearance()
    }

    private func refreshAppearance() {
        let showFill = isPointerInside || isPressed
        hoverBackground.isHidden = !showFill

        switch style {
        case .neutral:
            hoverBackground.layer?.backgroundColor = neutralFillColor.cgColor
            imageView.contentTintColor = neutralIconColor
        case .destructive:
            hoverBackground.layer?.backgroundColor = destructiveFillColor.cgColor
            imageView.contentTintColor = destructiveIconColor
        }
    }

    private var neutralFillColor: NSColor {
        if isOnSelectedTab {
            return NSColor.black.withAlphaComponent(isPressed ? 0.16 : 0.10)
        }
        return NSColor.white.withAlphaComponent(isPressed ? 0.28 : 0.18)
    }

    private var neutralIconColor: NSColor {
        guard isPointerInside || isPressed else { return idleTint }
        if isOnSelectedTab {
            return NSColor.black.withAlphaComponent(isPressed ? 0.78 : 0.68)
        }
        return NSColor.white.withAlphaComponent(isPressed ? 0.98 : 0.94)
    }

    private var destructiveFillColor: NSColor {
        if isPointerInside || isPressed {
            return NSColor.systemRed.withAlphaComponent(isPressed ? 0.92 : 0.82)
        }
        return .clear
    }

    private var destructiveIconColor: NSColor {
        if isPointerInside || isPressed {
            return .white
        }
        return idleTint
    }
}

@MainActor
private final class PaneTabItemView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 8
        static let titleLeadingInset: CGFloat = 9
        static let closeButtonWidth: CGFloat = 23
        static let moveButtonWidth: CGFloat = 20
    }

    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let selectButton = NSButton()
    private let closeButton: PaneTabChromeButton
    private let moveButtonStack = NSStackView()
    private var moveButtons: [PaneTabChromeButton] = []
    private let moveDirections: [PaneMoveDirection]
    private let selectionHandler: () -> Void
    private let closeHandler: () -> Void
    private let moveHandler: (PaneMoveDirection) -> Void
    private var isSelected = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(
        tab: PaneTabPresentation,
        isSelected: Bool,
        moveDirections: [PaneMoveDirection],
        selectionHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void,
        moveHandler: @escaping (PaneMoveDirection) -> Void
    ) {
        self.moveDirections = moveDirections
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        self.moveHandler = moveHandler
        closeButton = PaneTabChromeButton(
            systemSymbolName: "xmark",
            accessibilityDescription: "关闭窗口",
            pointSize: 9,
            style: .destructive
        )
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

        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        moveButtonStack.orientation = .horizontal
        moveButtonStack.spacing = 0
        moveButtonStack.alignment = .centerY
        moveButtonStack.distribution = .fillEqually
        for direction in moveDirections {
            let button = PaneTabChromeButton(
                systemSymbolName: direction.systemSymbolName,
                accessibilityDescription: direction.tooltip,
                pointSize: 10,
                style: .neutral
            )
            button.target = self
            button.action = #selector(moveButtonClicked(_:))
            button.tag = moveButtons.count
            moveButtons.append(button)
            moveButtonStack.addArrangedSubview(button)
        }

        addSubview(materialView)
        addSubview(tintView)
        addSubview(selectButton)
        addSubview(moveButtonStack)
        addSubview(closeButton)
        updateSelection(isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateMoveControlsVisibility()
        needsLayout = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateMoveControlsVisibility()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds

        let showMoves = shouldShowMoveControls
        let moveWidth = showMoves
            ? CGFloat(moveDirections.count) * Metrics.moveButtonWidth
            : 0
        moveButtonStack.isHidden = !showMoves
        moveButtonStack.frame = CGRect(
            x: bounds.width - Metrics.closeButtonWidth - moveWidth,
            y: 0,
            width: moveWidth,
            height: bounds.height
        )
        selectButton.frame = CGRect(
            x: Metrics.titleLeadingInset,
            y: 0,
            width: max(
                0,
                bounds.width - Metrics.closeButtonWidth - moveWidth - Metrics.titleLeadingInset
            ),
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

    @objc private func moveButtonClicked(_ sender: PaneTabChromeButton) {
        guard moveDirections.indices.contains(sender.tag) else { return }
        moveHandler(moveDirections[sender.tag])
    }

    func updateSelection(_ isSelected: Bool) {
        self.isSelected = isSelected
        // Keep every item independently frosted. The selected item receives an
        // almost opaque white tint, matching the reference while preserving a
        // trace of the material beneath it.
        tintView.layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.97).cgColor
            : NSColor.white.withAlphaComponent(0.13).cgColor

        let titleColor: NSColor = isSelected
            ? NSColor.black.withAlphaComponent(0.92)
            : NSColor.white.withAlphaComponent(0.94)
        let chromeColor: NSColor = isSelected
            ? NSColor.black.withAlphaComponent(0.48)
            : NSColor.white.withAlphaComponent(0.78)

        selectButton.contentTintColor = titleColor
        closeButton.updateChrome(isOnSelectedTab: isSelected, idleTint: chromeColor)
        for button in moveButtons {
            button.updateChrome(isOnSelectedTab: isSelected, idleTint: chromeColor)
        }

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isSelected ? 0.16 : 0.08
        layer?.shadowRadius = isSelected ? 2 : 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        updateMoveControlsVisibility()
        needsLayout = true
    }

    private var shouldShowMoveControls: Bool {
        !moveDirections.isEmpty && (isSelected || isHovered)
    }

    private func updateMoveControlsVisibility() {
        moveButtonStack.isHidden = !shouldShowMoveControls
    }
}

@MainActor
final class PaneTabBarPanel: NSPanel {
    private static let horizontalInset: CGFloat = 6
    private static let tabWidth: CGFloat = 154
    private static let tabSpacing: CGFloat = 4

    private let selectionHandler: (Int) -> Void
    private let closeHandler: (Int) -> Void
    private let moveHandler: (Int, PaneMoveDirection) -> Void
    private let moveDirections: [PaneMoveDirection]
    private let availableFrame: CGRect
    private let scrollView = NSScrollView()
    private let tabStripView = NSView()
    private var tabItemViews: [PaneTabItemView] = []
    private var tabs: [PaneTabPresentation]
    private var selectedIndex: Int

    init(
        frame: CGRect,
        tabs: [PaneTabPresentation],
        moveDirections: [PaneMoveDirection],
        selectionHandler: @escaping (Int) -> Void,
        closeHandler: @escaping (Int) -> Void,
        moveHandler: @escaping (Int, PaneMoveDirection) -> Void
    ) {
        self.selectionHandler = selectionHandler
        self.closeHandler = closeHandler
        self.moveHandler = moveHandler
        self.moveDirections = moveDirections
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
                moveDirections: moveDirections,
                selectionHandler: { [weak self] in self?.selectionHandler(index) },
                closeHandler: { [weak self] in self?.closeHandler(index) },
                moveHandler: { [weak self] direction in
                    self?.moveHandler(index, direction)
                }
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
