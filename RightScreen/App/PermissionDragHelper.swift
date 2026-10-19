import AppKit

/// 授权时吸附在「系统设置」窗口旁的小浮窗：把 RightScreen 图标拖进上方列表即可添加并开启。
/// 只在系统设置位于前台时显示，并跟随其窗口移动。
@MainActor
final class PermissionDragHelper {
    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    private static let panelSize = CGSize(width: 400, height: 76)

    private let panel: NSPanel
    private var followTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = Self.makeContent()
    }

    func start(for permission: AppPermission) {
        Permissions.openSettings(for: permission)
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.follow()
            }
        }
        // .common：拖动图标期间 run loop 处于 event tracking 模式，也要继续跟随。
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    func stop() {
        followTimer?.invalidate()
        followTimer = nil
        panel.orderOut(nil)
    }

    private func follow() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard
            frontmost == Self.settingsBundleIdentifier || frontmost == Bundle.main.bundleIdentifier,
            let settingsFrame = Self.settingsWindowFrame()
        else {
            panel.orderOut(nil)
            return
        }

        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: settingsFrame.midX, y: settingsFrame.midY)) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        // 按实际内容算尺寸：英文等较长文案会把浮窗撑宽，摆放时必须用真实宽度。
        let fitting = panel.contentView?.fittingSize ?? Self.panelSize
        let size = CGSize(width: max(fitting.width, Self.panelSize.width), height: Self.panelSize.height)
        let frame = PermissionHelperPlacement.frame(
            panelSize: size,
            settingsFrame: settingsFrame,
            visibleFrame: visibleFrame
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// 系统设置主窗口的 AppKit 坐标 frame；未打开或最小化时返回 nil。
    private static func settingsWindowFrame() -> CGRect? {
        guard
            let settings = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleIdentifier).first,
            let primaryScreen = NSScreen.screens.first,
            let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return nil
        }

        let frames = infos.compactMap { info -> CGRect? in
            guard
                info[kCGWindowOwnerPID as String] as? pid_t == settings.processIdentifier,
                info[kCGWindowLayer as String] as? Int == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width > 200, frame.height > 200
            else {
                return nil
            }
            return frame
        }
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        return ScreenFrameConversion.flippingY(largest, relativeTo: primaryScreen.frame)
    }

    private static func makeContent() -> NSView {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) ?? NSImage())
        arrow.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        arrow.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: localized("把 RightScreen 拖到上方列表中"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(labelWithString: localized("已在列表中？直接打开它的开关"))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        let dragSource = AppDragSourceView()

        let row = NSStackView(views: [arrow, texts, NSView(), dragSource])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.topAnchor.constraint(equalTo: background.topAnchor),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        return background
    }
}

/// 可拖动的 RightScreen 图标块；拖出的是 App 自身的文件 URL，系统设置的权限列表据此添加。
private final class AppDragSourceView: NSView, NSDraggingSource {
    private static let iconSize: CGFloat = 40

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        toolTip = localized("拖动到系统设置的列表中")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 128),
            heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var iconFrame: NSRect {
        NSRect(x: 6, y: (bounds.height - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage.draw(in: iconFrame)
        let name = NSAttributedString(
            string: "RightScreen",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        )
        let size = name.size()
        name.draw(at: NSPoint(x: iconFrame.maxX + 6, y: (bounds.height - size.height) / 2))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(iconFrame, contents: NSApp.applicationIconImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
