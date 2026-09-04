import AppKit

/// 拖拽分隔条时的玻璃预览：每格深灰底 + 居中 App Icon + 名称 + 尺寸。
@MainActor
final class BentoPreviewPanel: OverlayPanel {
    private let containerView = BentoPreviewContainerView()

    init(screenFrame: CGRect) {
        super.init(
            contentRect: screenFrame,
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
        contentView = containerView
        orderOut(nil)
    }

    func show(tiles: [BentoTilePresentation], in screenFrame: CGRect) {
        setFrame(screenFrame, display: true)
        containerView.screenFrame = screenFrame
        containerView.tiles = tiles
        orderFrontRegardless()
    }

    func hidePreview() {
        orderOut(nil)
        containerView.tiles = []
    }
}

@MainActor
private final class BentoPreviewContainerView: NSView {
    var screenFrame: CGRect = .zero
    var tiles: [BentoTilePresentation] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        for tile in tiles {
            let local = CGRect(
                x: tile.frame.minX - screenFrame.minX,
                y: tile.frame.minY - screenFrame.minY,
                width: tile.frame.width,
                height: tile.frame.height
            )
            drawTile(tile, in: local)
        }
    }

    private func drawTile(_ tile: BentoTilePresentation, in rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.18, alpha: 0.96).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.45, alpha: 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconSize: CGFloat = min(64, min(rect.width, rect.height) * 0.22)
        let iconRect = CGRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY + 8,
            width: iconSize,
            height: iconSize
        )

        if let icon = tile.applicationIcon {
            let drawn = icon.copy() as? NSImage ?? icon
            drawn.size = iconRect.size
            drawn.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
            NSBezierPath(roundedRect: iconRect, xRadius: 12, yRadius: 12).fill()
        }

        let titleRect = CGRect(
            x: rect.minX + 16,
            y: iconRect.minY - 28,
            width: rect.width - 32,
            height: 20
        )
        let title = NSAttributedString(
            string: tile.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: centeredParagraphStyle
            ]
        )
        title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        let sizeRect = CGRect(
            x: rect.minX + 16,
            y: titleRect.minY - 18,
            width: rect.width - 32,
            height: 16
        )
        let sizeText = NSAttributedString(
            string: tile.dimensionText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1),
                .paragraphStyle: centeredParagraphStyle
            ]
        )
        sizeText.draw(with: sizeRect, options: [.usesLineFragmentOrigin])
    }

    private var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }
}
