import AppKit
import SwiftUI

@MainActor
final class HotKeySettingsWindowController: NSWindowController {
    private let store: HotKeySettingsStore
    private let hotKeyCenter: HotKeyCenter
    private let recorder: HotKeyRecorder

    init(store: HotKeySettingsStore, hotKeyCenter: HotKeyCenter) {
        self.store = store
        self.hotKeyCenter = hotKeyCenter

        let recorder = HotKeyRecorder(store: store) { isRecording in
            if isRecording {
                hotKeyCenter.suspend()
            } else {
                hotKeyCenter.resume()
            }
        }
        self.recorder = recorder
        let view = HotKeySettingsView(store: store, recorder: recorder)
        let hosting = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localized("快捷键设置")
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone, .ignoresCycle]
        window.orderOut(nil)

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

extension HotKeySettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        recorder.stop()
        hotKeyCenter.resume()
    }
}
