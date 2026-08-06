import AppKit

@MainActor
final class LayoutCoordinator {
    private let windowIndexer = WindowIndexer()
    private let windowController = WindowController()
    private var refreshTimer: Timer?
    private var closingWindowIDs = Set<CGWindowID>()
    private(set) var session: LayoutSession?

    var hasActiveLayout: Bool {
        session != nil
    }

    func startLayout(_ kind: LayoutKind) {
        guard Permissions.isAccessibilityGranted else {
            Permissions.requestAccessibility()
            showMessage(
                title: "需要辅助功能权限",
                message: "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 RightScreen，然后再次选择布局。"
            )
            return
        }

        if session != nil {
            exitLayout()
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            showMessage(title: "无法开始布局", message: "RightScreen 未找到可用显示器。")
            return
        }

        let windows = windowIndexer.currentSpaceWindows()
        guard !windows.isEmpty else {
            showMessage(
                title: "没有可管理窗口",
                message: "请先打开至少一个普通 App 窗口；最小化、全屏和不可缩放窗口会被跳过。"
            )
            return
        }

        let windowsByPane = LayoutEngine.assign(windows, paneCount: kind.paneCount)
        let geometries = LayoutEngine.geometries(for: kind, in: screen.visibleFrame)
        let newSession = LayoutSession(
            kind: kind,
            screen: screen,
            windowsByPane: windowsByPane,
            geometries: geometries
        )
        session = newSession
        closingWindowIDs.removeAll()

        applyInitialLayout(newSession)
        createTabBars(for: newSession)
        startRefreshingWindows()
    }

    func exitLayout() {
        guard let session else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        self.session = nil
        closingWindowIDs.removeAll()

        for panel in session.panels.compactMap({ $0 }) {
            panel.orderOut(nil)
            panel.close()
        }

        for window in session.panes.flatMap(\.windows) {
            guard
                windowController.isAlive(window),
                let originalFrame = session.originalFrames[window.windowID]
            else {
                continue
            }
            windowController.setAccessibilityFrame(originalFrame, for: window)
        }
    }

    private func applyInitialLayout(_ session: LayoutSession) {
        for pane in session.panes where !pane.windows.isEmpty {
            for (index, window) in pane.windows.enumerated() {
                if index == pane.selectedIndex {
                    windowController.setAppKitFrame(
                        pane.geometry.windowFrame,
                        on: session.screen,
                        for: window
                    )
                } else {
                    windowController.moveOffscreen(window, relativeTo: session.screen)
                }
            }

            if let selectedWindow = pane.windows.first {
                windowController.raise(selectedWindow)
            }
        }
    }

    private func createTabBars(for session: LayoutSession) {
        for (paneIndex, pane) in session.panes.enumerated() where !pane.windows.isEmpty {
            createOrUpdateTabBar(forPane: paneIndex, in: session)
        }
    }

    private func createOrUpdateTabBar(forPane paneIndex: Int, in session: LayoutSession) {
        let pane = session.panes[paneIndex]
        guard !pane.windows.isEmpty else {
            session.panels[paneIndex]?.orderOut(nil)
            session.panels[paneIndex]?.close()
            session.panels[paneIndex] = nil
            return
        }

        if let panel = session.panels[paneIndex] {
            panel.updateTitles(pane.windows.map(\.tabTitle), selectedIndex: pane.selectedIndex)
        } else {
            let panel = PaneTabBarPanel(
                frame: pane.geometry.tabBarFrame,
                screenWidth: session.screen.visibleFrame.width,
                titles: pane.windows.map(\.tabTitle),
                selectionHandler: { [weak self] selectedIndex in
                    self?.selectTab(selectedIndex, inPane: paneIndex)
                },
                closeHandler: { [weak self] tabIndex in
                    self?.closeTab(tabIndex, inPane: paneIndex)
                }
            )
            session.panels[paneIndex] = panel
            panel.orderFrontRegardless()
        }
    }

    private func startRefreshingWindows() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.75,
            target: self,
            selector: #selector(refreshManagedWindows),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func refreshManagedWindows() {
        guard let session else { return }

        removeClosedWindows(from: session)

        let knownWindowIDs = Set(session.panes.flatMap(\.windows).map(\.windowID))
        let newWindows = windowIndexer.currentSpaceWindows().filter {
            !knownWindowIDs.contains($0.windowID) && !closingWindowIDs.contains($0.windowID)
        }
        for window in newWindows {
            addNewWindow(window, to: session)
        }
    }

    private func addNewWindow(_ window: ManagedWindow, to session: LayoutSession) {
        guard let paneIndex = session.panes.indices.min(by: {
            session.panes[$0].windows.count < session.panes[$1].windows.count
        }) else { return }

        var pane = session.panes[paneIndex]
        if pane.windows.indices.contains(pane.selectedIndex) {
            windowController.moveOffscreen(pane.windows[pane.selectedIndex], relativeTo: session.screen)
        }

        session.originalFrames[window.windowID] = window.frame
        pane.windows.append(window)
        pane.selectedIndex = pane.windows.count - 1
        session.panes[paneIndex] = pane

        windowController.setAppKitFrame(pane.geometry.windowFrame, on: session.screen, for: window)
        windowController.raise(window)
        createOrUpdateTabBar(forPane: paneIndex, in: session)
    }

    private func removeClosedWindows(from session: LayoutSession) {
        for paneIndex in session.panes.indices {
            var pane = session.panes[paneIndex]
            let selectedID = pane.windows.indices.contains(pane.selectedIndex)
                ? pane.windows[pane.selectedIndex].windowID
                : nil
            let liveWindows = pane.windows.filter(windowController.isAlive)
            guard liveWindows.count != pane.windows.count else { continue }

            pane.windows = liveWindows
            if let selectedID, let retainedIndex = liveWindows.firstIndex(where: { $0.windowID == selectedID }) {
                pane.selectedIndex = retainedIndex
            } else {
                pane.selectedIndex = min(pane.selectedIndex, max(0, liveWindows.count - 1))
                if let selected = liveWindows.indices.contains(pane.selectedIndex)
                    ? liveWindows[pane.selectedIndex]
                    : nil {
                    windowController.setAppKitFrame(
                        pane.geometry.windowFrame,
                        on: session.screen,
                        for: selected
                    )
                    windowController.raise(selected)
                }
            }
            session.panes[paneIndex] = pane
            createOrUpdateTabBar(forPane: paneIndex, in: session)
        }
    }

    private func selectTab(_ selectedIndex: Int, inPane paneIndex: Int) {
        guard
            let session,
            session.panes.indices.contains(paneIndex),
            session.panes[paneIndex].windows.indices.contains(selectedIndex)
        else {
            return
        }

        let pane = session.panes[paneIndex]
        for (index, window) in pane.windows.enumerated() {
            if index == selectedIndex {
                windowController.setAppKitFrame(
                    pane.geometry.windowFrame,
                    on: session.screen,
                    for: window
                )
                windowController.raise(window)
            } else {
                windowController.moveOffscreen(window, relativeTo: session.screen)
            }
        }
        session.panes[paneIndex].selectedIndex = selectedIndex
        createOrUpdateTabBar(forPane: paneIndex, in: session)
    }

    private func closeTab(_ tabIndex: Int, inPane paneIndex: Int) {
        guard
            let session,
            session.panes.indices.contains(paneIndex),
            session.panes[paneIndex].windows.indices.contains(tabIndex)
        else {
            return
        }

        var pane = session.panes[paneIndex]
        let window = pane.windows[tabIndex]
        guard windowController.close(window) else {
            showMessage(title: "无法关闭窗口", message: "这个 App 不允许 RightScreen 通过辅助功能关闭该窗口。")
            return
        }

        closingWindowIDs.insert(window.windowID)
        session.originalFrames.removeValue(forKey: window.windowID)
        let wasSelected = tabIndex == pane.selectedIndex
        pane.windows.remove(at: tabIndex)

        if pane.windows.isEmpty {
            pane.selectedIndex = 0
        } else if tabIndex < pane.selectedIndex {
            pane.selectedIndex -= 1
        } else {
            pane.selectedIndex = min(pane.selectedIndex, pane.windows.count - 1)
        }
        session.panes[paneIndex] = pane

        if wasSelected, !pane.windows.isEmpty {
            let replacement = pane.windows[pane.selectedIndex]
            windowController.setAppKitFrame(
                pane.geometry.windowFrame,
                on: session.screen,
                for: replacement
            )
            windowController.raise(replacement)
        }
        createOrUpdateTabBar(forPane: paneIndex, in: session)
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
