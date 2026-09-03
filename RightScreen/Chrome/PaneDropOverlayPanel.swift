import AppKit

/// Tab Mode 拖入格位时的淡蓝半透明蒙版。必须忽略鼠标，否则会抢走 Chrome 松手落点。
@MainActor
final class PaneDropOverlayPanel: NSPanel {
    private let fillView = PaneDropOverlayView()

    init() {
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
        applyOverlaySpaceBehavior()
        ignoresMouseEvents = true
        contentView = fillView
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(over paneFrame: CGRect) {
        setFrame(paneFrame, display: true)
        fillView.needsDisplay = true
        orderFrontRegardless()
    }

    func hideOverlay() {
        orderOut(nil)
    }
}

@MainActor
private final class PaneDropOverlayView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        let inset = bounds.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.62).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
