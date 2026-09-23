import AppKit

struct PaneTabPresentation: Equatable {
    let title: String
    let ownerPID: pid_t

    /// 同一进程的 Icon 只缩放一次；Tab 条频繁刷新时不再反复拷贝图像。
    @MainActor private static var iconCache: [pid_t: NSImage] = [:]

    @MainActor var applicationIcon: NSImage? {
        if let cached = Self.iconCache[ownerPID] {
            return cached
        }
        guard let icon = NSRunningApplication(processIdentifier: ownerPID)?.icon else {
            return nil
        }
        let scaledIcon = (icon.copy() as? NSImage) ?? icon
        scaledIcon.size = CGSize(width: 13, height: 13)
        Self.iconCache[ownerPID] = scaledIcon
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
    }

    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let selectButton = NSButton()
    private let closeButton: PaneTabChromeButton
    private let moveButtonStack = NSStackView()
    private var moveButtons: [PaneTabChromeButton] = []
    private let moveDirections: [PaneMoveDirection]
    private let selectionHandler: (Int) -> Void
    private let closeHandler: (Int) -> Void
    private let moveHandler: (Int, PaneMoveDirection) -> Void
    private var tab: PaneTabPresentation?
    private var isSelected = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    /// 当前对应的 Tab 下标；视图复用时随之更新，回调总是报告最新下标。
    var tabIndex = 0
    var displayMode: PaneTabDisplayMode = .full {
        didSet {
            guard displayMode != oldValue else { return }
            applyDisplayMode()
        }
    }

    init(
        moveDirections: [PaneMoveDirection],
        selectionHandler: @escaping (Int) -> Void,
        closeHandler: @escaping (Int) -> Void,
        moveHandler: @escaping (Int, PaneMoveDirection) -> Void
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

        selectButton.imageScaling = .scaleProportionallyDown
        selectButton.imageHugsTitle = true
        selectButton.isBordered = false
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
        applyDisplayMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tab: PaneTabPresentation, isSelected: Bool) {
        if self.tab != tab {
            self.tab = tab
            let icon = tab.applicationIcon
            selectButton.image = icon
            selectButton.toolTip = tab.title
            selectButton.setAccessibilityLabel(tab.title)
            applyDisplayMode()
        }
        if self.isSelected != isSelected || tintView.layer?.backgroundColor == nil {
            updateSelection(isSelected)
        }
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
        needsLayout = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsLayout = true
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds

        let closeWidth = PaneTabStripLayout.closeButtonWidth
        let showMoves = shouldShowMoveControls
        let moveWidth = showMoves
            ? CGFloat(moveDirections.count) * PaneTabStripLayout.moveButtonWidth
            : 0
        moveButtonStack.isHidden = !showMoves
        moveButtonStack.frame = CGRect(
            x: bounds.width - closeWidth - moveWidth,
            y: 0,
            width: moveWidth,
            height: bounds.height
        )
        let leading = displayMode == .full ? Metrics.titleLeadingInset : 0
        let selectWidth = displayMode == .full
            ? bounds.width - closeWidth - moveWidth - leading
            : PaneTabStripLayout.iconAreaWidth
        selectButton.frame = CGRect(
            x: leading,
            y: 0,
            width: max(0, selectWidth),
            height: bounds.height
        )
        closeButton.frame = CGRect(
            x: bounds.width - closeWidth,
            y: 0,
            width: closeWidth,
            height: bounds.height
        )
    }

    @objc private func selectTab() {
        selectionHandler(tabIndex)
    }

    @objc private func closeWindow() {
        closeHandler(tabIndex)
    }

    @objc private func moveButtonClicked(_ sender: PaneTabChromeButton) {
        guard moveDirections.indices.contains(sender.tag) else { return }
        moveHandler(tabIndex, moveDirections[sender.tag])
    }

    private func applyDisplayMode() {
        let hasIcon = selectButton.image != nil
        if displayMode == .full || !hasIcon {
            selectButton.title = tab?.title ?? ""
            selectButton.imagePosition = hasIcon ? .imageLeading : .noImage
            selectButton.alignment = .left
        } else {
            selectButton.title = ""
            selectButton.imagePosition = .imageOnly
            selectButton.alignment = .center
        }
        needsLayout = true
    }

    private func updateSelection(_ isSelected: Bool) {
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

        needsLayout = true
    }

    /// 最小档（只剩 Icon + 关闭）不再显示换格按钮；换格仍可用快捷键。
    private var shouldShowMoveControls: Bool {
        guard !moveDirections.isEmpty, displayMode != .iconOnly else { return false }
        // 纯 Icon 档的宽度已经给换格按钮留了位置，常显即可，避免悬停时挤压 Icon。
        if displayMode == .iconWithMoves { return true }
        return isSelected || isHovered
    }
}

/// Tab 太多、最小形态也放不下时的「+N」按钮，点开菜单选其余 Tab。
@MainActor
private final class PaneTabOverflowButton: NSView {
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let button = NSButton()
    private var entries: [(index: Int, tab: PaneTabPresentation)] = []
    private let selectionHandler: (Int) -> Void

    init(selectionHandler: @escaping (Int) -> Void) {
        self.selectionHandler = selectionHandler
        super.init(frame: .zero)
        wantsLayer = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 8
        materialView.layer?.masksToBounds = true

        tintView.wantsLayer = true
        tintView.layer?.cornerRadius = 8
        tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor

        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.94)
        button.target = self
        button.action = #selector(showMenu)

        addSubview(materialView)
        addSubview(tintView)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [(index: Int, tab: PaneTabPresentation)]) {
        self.entries = entries
        button.title = "+\(entries.count)"
        button.toolTip = "还有 \(entries.count) 个窗口"
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds
        button.frame = bounds
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        for entry in entries {
            let item = NSMenuItem(title: entry.tab.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = entry.index
            item.image = entry.tab.applicationIcon
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        selectionHandler(sender.tag)
    }
}

@MainActor
final class PaneTabBarPanel: OverlayPanel {
    private static let horizontalInset: CGFloat = 6
    private static let verticalInset: CGFloat = 4
    private static let animationDuration: TimeInterval = 0.18

    private let selectionHandler: (Int) -> Void
    private let closeHandler: (Int) -> Void
    private let moveHandler: (Int, PaneMoveDirection) -> Void
    private let moveDirections: [PaneMoveDirection]
    private var availableFrame: CGRect
    private let tabStripView = NSView()
    private var tabItemViews: [PaneTabItemView] = []
    private lazy var overflowButton = PaneTabOverflowButton { [weak self] index in
        self?.selectionHandler(index)
    }
    private var tabs: [PaneTabPresentation]
    private var selectedIndex: Int
    private var stripLayout: PaneTabStripLayout?

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
        contentView?.addSubview(tabStripView)
        applyLayout(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func configurePanel() {
        level = .floating
        applyOverlaySpaceBehavior()
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func updateTabs(_ tabs: [PaneTabPresentation], selectedIndex: Int, frame: CGRect) {
        let resolvedSelection = tabs.indices.contains(selectedIndex) ? selectedIndex : -1
        guard
            tabs != self.tabs
                || resolvedSelection != self.selectedIndex
                || frame != availableFrame
        else {
            return
        }
        // 窗格尺寸变了（换屏）直接落位；Tab 增删、切换才做过渡动画。
        let animated = frame.size == availableFrame.size && isVisible
        availableFrame = frame
        self.tabs = tabs
        self.selectedIndex = resolvedSelection
        applyLayout(animated: animated)
    }

    /// 复用已有 Tab 视图，只增删差额并就地更新内容；
    /// 宽度、位置变化用短动画过渡，不再整条销毁重建，避免切换时整条闪一下。
    private func applyLayout(animated: Bool) {
        let itemHeight = max(0, availableFrame.height - Self.verticalInset * 2)
        let layout = PaneTabStripLayout.make(
            tabCount: tabs.count,
            selectedIndex: selectedIndex,
            moveCount: moveDirections.count,
            availableWidth: availableFrame.width - Self.horizontalInset * 2
        )
        let previousLayout = stripLayout
        stripLayout = layout

        while tabItemViews.count > layout.visibleIndices.count {
            tabItemViews.removeLast().removeFromSuperview()
        }
        var insertedViews: [PaneTabItemView] = []
        while tabItemViews.count < layout.visibleIndices.count {
            let item = PaneTabItemView(
                moveDirections: moveDirections,
                selectionHandler: { [weak self] index in self?.selectionHandler(index) },
                closeHandler: { [weak self] index in self?.closeHandler(index) },
                moveHandler: { [weak self] index, direction in self?.moveHandler(index, direction) }
            )
            let slot = tabItemViews.count
            item.frame = CGRect(
                x: layout.tabOriginX(atSlot: slot),
                y: 0,
                width: layout.tabWidth,
                height: itemHeight
            )
            tabStripView.addSubview(item)
            tabItemViews.append(item)
            insertedViews.append(item)
        }

        for (slot, tabIndex) in layout.visibleIndices.enumerated() {
            let item = tabItemViews[slot]
            item.tabIndex = tabIndex
            item.displayMode = layout.mode
            item.update(tab: tabs[tabIndex], isSelected: tabIndex == selectedIndex)
        }

        if layout.showsOverflow {
            if overflowButton.superview == nil {
                tabStripView.addSubview(overflowButton)
            }
            overflowButton.update(entries: layout.hiddenIndices.map { ($0, tabs[$0]) })
        } else {
            overflowButton.removeFromSuperview()
        }

        let stripWidth = layout.stripWidth
        let panelWidth = min(availableFrame.width, stripWidth + Self.horizontalInset * 2)
        let targetPanelFrame = CGRect(
            x: availableFrame.minX,
            y: availableFrame.minY,
            width: panelWidth,
            height: availableFrame.height
        )
        let isShrinking = targetPanelFrame.width < frame.width
        let shouldAnimate = animated && previousLayout != nil

        // 变宽时先把面板撑开再播放动画；变窄时等动画结束再收，免得尾部被截掉。
        if !shouldAnimate || !isShrinking {
            setFrameIfNeeded(targetPanelFrame)
        }
        tabStripView.frame = CGRect(
            x: Self.horizontalInset,
            y: Self.verticalInset,
            width: max(stripWidth, frame.width - Self.horizontalInset * 2),
            height: itemHeight
        )

        let placeItems = { [self] (animate: Bool) in
            for slot in tabItemViews.indices {
                let target = CGRect(
                    x: layout.tabOriginX(atSlot: slot),
                    y: 0,
                    width: layout.tabWidth,
                    height: itemHeight
                )
                if animate {
                    tabItemViews[slot].animator().frame = target
                } else {
                    tabItemViews[slot].frame = target
                }
            }
            if layout.showsOverflow {
                let target = CGRect(
                    x: layout.overflowOriginX,
                    y: 0,
                    width: PaneTabStripLayout.overflowWidth,
                    height: itemHeight
                )
                if animate {
                    overflowButton.animator().frame = target
                } else {
                    overflowButton.frame = target
                }
            }
        }

        guard shouldAnimate else {
            placeItems(false)
            return
        }

        for item in insertedViews {
            item.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            placeItems(true)
            for item in insertedViews {
                item.animator().alphaValue = 1
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.stripLayout == layout else { return }
                self.setFrameIfNeeded(targetPanelFrame)
            }
        }
    }

    private func setFrameIfNeeded(_ target: CGRect) {
        guard frame != target else { return }
        setFrame(target, display: true)
    }
}
