import AppKit
import SwiftUI

@MainActor
@Observable
final class PermissionGuideModel {
    private(set) var granted: Set<AppPermission> = []
    private(set) var signingIssue: String?
    /// 刚授权完的那一刻回调，用来收起拖动浮窗并把引导窗口拉回前台。
    var onPermissionGranted: (() -> Void)?
    var onAuthorize: ((AppPermission) -> Void)?

    private var pollTask: Task<Void, Never>?

    var allGranted: Bool {
        signingIssue == nil && granted.count == AppPermission.allCases.count
    }

    func startPolling() {
        refresh()
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        signingIssue = Permissions.signingIssue
        let current = Set(AppPermission.allCases.filter(Permissions.isGranted))
        let newlyGranted = !current.subtracting(granted).isEmpty
        granted = current
        if newlyGranted {
            onPermissionGranted?()
        }
    }

    func authorize(_ permission: AppPermission) {
        onAuthorize?(permission)
    }
}

struct PermissionGuideView: View {
    let model: PermissionGuideModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("设置 RightScreen")).font(.title3.bold())
                    Text(model.allGranted ? localized("一切就绪") : localized("开启以下权限后即可使用"))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(AppPermission.allCases) { permission in
                    row(permission)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if let issue = model.signingIssue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if model.allGranted {
                    Button(localized("开始使用"), action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(localized("稍后"), action: onClose)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func row(_ permission: AppPermission) -> some View {
        HStack(spacing: 12) {
            Image(systemName: permission.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.settingsName).font(.headline)
                Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.granted.contains(permission) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                Button(localized("授权")) { model.authorize(permission) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.signingIssue != nil)
            }
        }
        .padding(12)
    }
}

@MainActor
final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {
    private let model = PermissionGuideModel()
    private let dragHelper = PermissionDragHelper()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        super.init(window: window)

        let view = PermissionGuideView(model: model) { [weak self] in
            self?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self

        model.onAuthorize = { [weak self] permission in
            self?.dragHelper.start(for: permission)
        }
        model.onPermissionGranted = { [weak self] in
            guard let self else { return }
            self.dragHelper.stop()
            if self.window?.isVisible == true {
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 有权限未授权（或安装包身份不对）时才弹出；全部就绪返回 false。
    @discardableResult
    func showIfNeeded() -> Bool {
        let needsGuide = Permissions.signingIssue != nil || !AppPermission.allCases.allSatisfy(Permissions.isGranted)
        guard needsGuide else { return false }
        show()
        return true
    }

    func show() {
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        dragHelper.stop()
    }
}
