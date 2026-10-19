import AppKit

/// 授权时贴在「系统设置」权限列表正下方的一行提示条。
/// 整条可拖动：列表里没有 RightScreen 时，把它拖进上方列表即可添加。
/// 迟迟未生效时文案换成「删除旧条目后重新授权」，见 `PermissionHelperHint`。
/// 只在系统设置位于前台时显示，并跟随其窗口移动。
@MainActor
final class PermissionDragHelper {
    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    private static let pillHeight: CGFloat = 36

    private let panel: NSPanel
    private let pill = HelperPillView(text: PermissionHelperHint.turnOnOrDrag.text)
    private var followTimer: Timer?
    private var startedAt = Date()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: Self.pillHeight),
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
        panel.contentView = pill
    }

    func start(for permission: AppPermission) {
        // 先让系统把 RightScreen 登记进列表，用户打开开关即可；拖动只是登记失败时的后备。
        Permissions.registerInSettingsList(permission)
        Permissions.openSettings(for: permission)
        startedAt = Date()
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.follow()
            }
        }
        // .common：拖动期间 run loop 处于 event tracking 模式，也要继续跟随。
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
        pill.text = PermissionHelperHint.resolve(secondsSinceStart: Date().timeIntervalSince(startedAt)).text
        let frame = PermissionHelperPlacement.frame(
            panelSize: CGSize(width: pill.fittingSize.width, height: Self.pillHeight),
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
}

/// 一行胶囊提示：App 图标 + 文案。整条都是拖动源，拖出的是 App 自身的文件 URL。
private final class HelperPillView: NSVisualEffectView, NSDraggingSource {
    private let iconView = NSImageView(image: NSApp.applicationIconImage)
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            toolTip = newValue
        }
    }

    init(text: String) {
        super.init(frame: .zero)
        material = .popover
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.stringValue = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 子视图（文字、图标）不截获鼠标，整条都能拖。
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(iconView.frame(in: self), contents: NSApp.applicationIconImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}

private extension NSView {
    func frame(in ancestor: NSView) -> NSRect {
        superview?.convert(frame, to: ancestor) ?? frame
    }
}
