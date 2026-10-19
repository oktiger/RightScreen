import AppKit
import SwiftUI

@MainActor
@Observable
final class PermissionGuideModel {
    private(set) var stage: PermissionGuideStage = .needsGrant
    private var settingsOpenedAt: Date?
    private var pollTask: Task<Void, Never>?

    func startPolling() {
        refresh()
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
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
        stage = PermissionGuideStage.resolve(
            signingIssue: Permissions.signingIssue,
            isTrusted: Permissions.isAccessibilityGranted,
            secondsSinceSettingsOpened: settingsOpenedAt.map { Date().timeIntervalSince($0) }
        )
    }

    /// 触发系统授权提示（把 RightScreen 加入列表）并直接打开“辅助功能”设置页。
    func requestAndOpenSettings() {
        if settingsOpenedAt == nil {
            settingsOpenedAt = Date()
        }
        Permissions.openAccessibilitySettings(promptIfNeeded: true)
        refresh()
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

struct PermissionGuideView: View {
    let model: PermissionGuideModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch model.stage {
            case let .signingIssue(issue):
                Text(Permissions.accessibilityHelpMessage(signingIssue: issue).message)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            case .granted:
                Text(localized("RightScreen 已获得辅助功能权限，可以从菜单栏图标选择布局开始使用。"))
                    .fixedSize(horizontal: false, vertical: true)
            case .needsGrant, .waitingForToggle, .stuck:
                steps
                troubleshooting
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .frame(width: 500)
        .frame(minHeight: 380)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                statusLine
            }
        }
    }

    private var title: String {
        switch model.stage {
        case .signingIssue: localized("辅助功能授权无法保持")
        case .granted: localized("权限已就绪")
        default: localized("需要辅助功能权限")
        }
    }

    private var statusLine: some View {
        let granted = model.stage == .granted
        return Label(
            granted ? localized("辅助功能：已授权") : localized("辅助功能：未授权"),
            systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .foregroundStyle(granted ? Color.green : Color.red)
        .font(.callout)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("RightScreen 需要“辅助功能”权限才能移动和调整其他 App 的窗口。"))
                .fixedSize(horizontal: false, vertical: true)
            Text(localized("""
            1. 点击下方“打开系统设置”；
            2. 在“隐私与安全性 → 辅助功能”列表中打开 RightScreen 的开关；
            3. 回到这里，状态会自动变为“已授权”。
            """))
            .fixedSize(horizontal: false, vertical: true)
            if model.stage == .waitingForToggle {
                Text(localized("正在等待授权…"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var troubleshooting: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("开关已经打开，却仍显示未授权？"))
                    .font(.headline)
                Text(localized("""
                这通常是系统中残留了旧版本 RightScreen（之前安装过的测试版或其他渠道的版本）的授权记录，新版本无法沿用。请：
                1. 在“辅助功能”列表中选中 RightScreen，点击下方的“−”将其删除；
                2. 回到这里点击“打开系统设置”，重新打开 RightScreen 的开关；
                3. 若仍未生效，点击“重新启动 RightScreen”。
                """))
                .fixedSize(horizontal: false, vertical: true)
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .overlay {
            if model.stage == .stuck {
                RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 1.5)
            }
        }
    }

    private var buttons: some View {
        HStack {
            switch model.stage {
            case .granted:
                Spacer()
                Button(localized("开始使用"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            case .signingIssue:
                Spacer()
                Button(localized("好"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            case .needsGrant, .waitingForToggle, .stuck:
                Button(localized("重新启动 RightScreen")) { model.relaunch() }
                Spacer()
                Button(localized("稍后"), action: onClose)
                Button(localized("打开系统设置")) { model.requestAndOpenSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {
    private let model = PermissionGuideModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightScreen"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        super.init(window: window)

        let view = PermissionGuideView(model: model) { [weak self] in
            self?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 未授权或签名有问题时才弹出；已授权返回 false。
    @discardableResult
    func showIfNeeded() -> Bool {
        guard Permissions.signingIssue != nil || !Permissions.isAccessibilityGranted else {
            return false
        }
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
    }
}
