import AppKit

/// 管理 Bento 分隔条把手：每条分割线一块窄浮层，不遮挡窗格内容点击。
@MainActor
final class BentoDividerController {
    private var handlePanels: [BentoDividerHandlePanel] = []
    private let onDragBegan: (_ path: [BentoChildSlot]) -> Void
    private let onDragChanged: (_ path: [BentoChildSlot], _ locationInScreen: CGPoint) -> Void
    private let onDragEnded: () -> Void

    init(
        onDragBegan: @escaping (_ path: [BentoChildSlot]) -> Void,
        onDragChanged: @escaping (_ path: [BentoChildSlot], _ locationInScreen: CGPoint) -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.onDragBegan = onDragBegan
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    func update(dividers: [BentoDividerLayout]) {
        while handlePanels.count > dividers.count {
            let panel = handlePanels.removeLast()
            panel.orderOut(nil)
            panel.close()
        }
        while handlePanels.count < dividers.count {
            let panel = BentoDividerHandlePanel(
                onDragBegan: { [weak self] path in
                    self?.onDragBegan(path)
                },
                onDragChanged: { [weak self] path, location in
                    self?.onDragChanged(path, location)
                },
                onDragEnded: { [weak self] in
                    self?.onDragEnded()
                }
            )
            handlePanels.append(panel)
        }

        for (panel, divider) in zip(handlePanels, dividers) {
            panel.update(divider: divider)
        }
    }

    func tearDown() {
        for panel in handlePanels {
            panel.orderOut(nil)
            panel.close()
        }
        handlePanels.removeAll()
    }
}

@MainActor
private final class BentoDividerHandlePanel: NSPanel {
    private let handleView: BentoDividerHandleView

    init(
        onDragBegan: @escaping (_ path: [BentoChildSlot]) -> Void,
        onDragChanged: @escaping (_ path: [BentoChildSlot], _ locationInScreen: CGPoint) -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        handleView = BentoDividerHandleView(
            onDragBegan: onDragBegan,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = handleView
        ignoresMouseEvents = false
    }

    func update(divider: BentoDividerLayout) {
        setFrame(divider.hitFrame, display: true)
        handleView.divider = divider
        orderFrontRegardless()
    }
}

@MainActor
private final class BentoDividerHandleView: NSView {
    var divider: BentoDividerLayout? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private let onDragBegan: (_ path: [BentoChildSlot]) -> Void
    private let onDragChanged: (_ path: [BentoChildSlot], _ locationInScreen: CGPoint) -> Void
    private let onDragEnded: () -> Void
    private var isDragging = false

    init(
        onDragBegan: @escaping (_ path: [BentoChildSlot]) -> Void,
        onDragChanged: @escaping (_ path: [BentoChildSlot], _ locationInScreen: CGPoint) -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.onDragBegan = onDragBegan
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard let divider else { return }
        let cursor: NSCursor = divider.orientation == .vertical ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let divider else { return }
        isDragging = true
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        onDragBegan(divider.path)
        onDragChanged(divider.path, point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let divider else { return }
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        onDragChanged(divider.path, point)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let divider else { return }

        let visible = divider.frame
        let panelFrame = window?.frame ?? .zero
        let localVisible = CGRect(
            x: visible.minX - panelFrame.minX,
            y: visible.minY - panelFrame.minY,
            width: visible.width,
            height: visible.height
        )

        let handleLength: CGFloat = 28
        let handleThickness: CGFloat = 4
        let handleRect: CGRect
        switch divider.orientation {
        case .vertical:
            handleRect = CGRect(
                x: localVisible.midX - handleThickness / 2,
                y: localVisible.midY - handleLength / 2,
                width: handleThickness,
                height: handleLength
            )
        case .horizontal:
            handleRect = CGRect(
                x: localVisible.midX - handleLength / 2,
                y: localVisible.midY - handleThickness / 2,
                width: handleLength,
                height: handleThickness
            )
        }

        let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
        NSColor(calibratedWhite: 0.82, alpha: 0.92).setFill()
        path.fill()
    }
}
