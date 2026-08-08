import AppKit

@MainActor
final class LayoutCoordinator {
    private static let requiredNewWindowSightings = 3

    private let windowIndexer = WindowIndexer()
    private let windowController = WindowController()
    private var refreshTimer: Timer?
    private var closingWindowIDs = Set<CGWindowID>()
    private var pendingWindowSightings: [CGWindowID: Int] = [:]
    private(set) var session: LayoutSession?
    private(set) var bentoSession: BentoSession?

    var hasActiveLayout: Bool {
        session != nil || bentoSession != nil
    }

    var isBentoActive: Bool {
        bentoSession != nil
    }

    func startLayout(_ kind: LayoutKind) {
        guard ensureAccessibility() else { return }
        guard let screen = primaryScreen() else { return }
        guard let windows = manageableWindows() else { return }

        exitLayout()

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
        pendingWindowSightings.removeAll()

        applyInitialLayout(newSession)
        createTabBars(for: newSession)
        startRefreshingWindows()
    }

    func startBento() {
        guard ensureAccessibility() else { return }
        guard let screen = primaryScreen() else { return }
        guard let windows = manageableWindows() else { return }
        guard let tree = BentoEngine.buildTree(windows) else { return }

        exitLayout()

        let newSession = BentoSession(screen: screen, windows: windows, tree: tree)
        bentoSession = newSession
        closingWindowIDs.removeAll()
        pendingWindowSightings.removeAll()

        applyBentoFrames(newSession)
        installBentoChrome(for: newSession)
        startRefreshingWindows()
    }

    func exitLayout() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        closingWindowIDs.removeAll()
        pendingWindowSightings.removeAll()

        if let session {
            self.session = nil
            for panel in session.panels.compactMap({ $0 }) {
                panel.orderOut(nil)
                panel.close()
            }
            restoreOriginalFrames(session.originalFrames, windows: session.panes.flatMap(\.windows))
        }

        if let bentoSession {
            self.bentoSession = nil
            bentoSession.dividerController?.tearDown()
            bentoSession.previewPanel?.hidePreview()
            bentoSession.previewPanel?.close()
            restoreOriginalFrames(
                bentoSession.originalFrames,
                windows: BentoEngine.leafValues(bentoSession.tree)
            )
        }
    }

    // MARK: - Bento

    private func installBentoChrome(for session: BentoSession) {
        let preview = BentoPreviewPanel(screenFrame: session.rootFrame)
        session.previewPanel = preview

        let dividers = BentoDividerController(
            onDragBegan: { [weak self] _ in
                self?.beginBentoDividerDrag()
            },
            onDragChanged: { [weak self] path, location in
                self?.updateBentoDividerDrag(path: path, locationInScreen: location)
            },
            onDragEnded: { [weak self] in
                self?.endBentoDividerDrag()
            }
        )
        session.dividerController = dividers
        dividers.update(dividers: session.dividerLayouts())
    }

    private func applyBentoFrames(_ session: BentoSession) {
        for leaf in session.leafLayouts() {
            windowController.setAppKitFrame(leaf.frame, on: session.screen, for: leaf.value)
            windowController.raise(leaf.value)
        }
    }

    private func beginBentoDividerDrag() {
        guard let session = bentoSession else { return }
        session.isDraggingDivider = true
        session.previewPanel?.show(tiles: session.tilePresentations(), in: session.rootFrame)
    }

    private func updateBentoDividerDrag(path: [BentoChildSlot], locationInScreen: CGPoint) {
        guard let session = bentoSession else { return }
        guard
            let splitFrame = BentoEngine.splitFrame(
                at: path,
                in: session.tree,
                rootFrame: session.rootFrame,
                gap: session.gap
            )
        else {
            return
        }

        let orientation: BentoSplitOrientation
        if let match = session.dividerLayouts().first(where: { $0.path == path }) {
            orientation = match.orientation
        } else {
            return
        }

        let location = orientation == .vertical ? locationInScreen.x : locationInScreen.y
        session.tree = BentoEngine.updatingRatio(
            in: session.tree,
            path: path,
            location: location,
            splitFrame: splitFrame,
            gap: session.gap
        )
        session.previewPanel?.show(tiles: session.tilePresentations(), in: session.rootFrame)
        session.dividerController?.update(dividers: session.dividerLayouts())
        // 预览全屏且 ignoresMouseEvents；保持其在把手之上，事件仍穿透到下层把手。
        session.previewPanel?.orderFrontRegardless()
    }

    private func endBentoDividerDrag() {
        guard let session = bentoSession else { return }
        session.isDraggingDivider = false
        session.previewPanel?.hidePreview()
        applyBentoFrames(session)
        session.dividerController?.update(dividers: session.dividerLayouts())
    }

    private func refreshBentoSession(_ session: BentoSession) {
        guard !session.isDraggingDivider else { return }

        let previousValues = BentoEngine.leafValues(session.tree)
        let liveWindows = previousValues.filter(windowController.isAlive)
        if liveWindows.count != previousValues.count {
            if liveWindows.isEmpty {
                exitLayout()
                return
            }
            if let rebuilt = BentoEngine.buildTree(liveWindows) {
                session.tree = rebuilt
                applyBentoFrames(session)
                session.dividerController?.update(dividers: session.dividerLayouts())
            }
        }

        let knownIDs = Set(liveWindows.map(\.windowID))
        let candidates = windowIndexer.currentSpaceWindows().filter { candidate in
            !knownIDs.contains(candidate.windowID)
                && !closingWindowIDs.contains(candidate.windowID)
                && !liveWindows.contains(where: { $0.refersToSameAccessibilityWindow(as: candidate) })
        }

        let visibleCandidateIDs = Set(candidates.map(\.windowID))
        pendingWindowSightings = pendingWindowSightings.filter {
            visibleCandidateIDs.contains($0.key)
        }

        for candidate in candidates {
            let sightings = pendingWindowSightings[candidate.windowID, default: 0] + 1
            guard sightings >= Self.requiredNewWindowSightings else {
                pendingWindowSightings[candidate.windowID] = sightings
                continue
            }
            pendingWindowSightings.removeValue(forKey: candidate.windowID)
            addNewWindowToBento(candidate, session: session)
        }
    }

    private func addNewWindowToBento(_ window: ManagedWindow, session: BentoSession) {
        var windows = BentoEngine.leafValues(session.tree)
        guard
            !windows.contains(where: { $0.windowID == window.windowID }),
            !windows.contains(where: { $0.refersToSameAccessibilityWindow(as: window) })
        else {
            return
        }

        session.originalFrames[window.windowID] = window.frame
        windows.append(window)
        guard let rebuilt = BentoEngine.buildTree(windows) else { return }
        session.tree = rebuilt
        applyBentoFrames(session)
        session.dividerController?.update(dividers: session.dividerLayouts())
    }

    // MARK: - Tab layout (existing)

    private func applyInitialLayout(_ session: LayoutSession) {
        for pane in session.panes where !pane.windows.isEmpty {
            for window in pane.windows {
                windowController.setAppKitFrame(
                    pane.geometry.windowFrame,
                    on: session.screen,
                    for: window
                )
            }

            if pane.windows.indices.contains(pane.selectedIndex) {
                let selectedWindow = pane.windows[pane.selectedIndex]
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
            panel.updateTabs(
                pane.windows.map(makeTabPresentation),
                selectedIndex: pane.selectedIndex
            )
            panel.orderFrontRegardless()
        } else {
            let panel = PaneTabBarPanel(
                frame: pane.geometry.tabBarFrame,
                tabs: pane.windows.map(makeTabPresentation),
                moveDirections: PaneMove.availableDirections(
                    from: paneIndex,
                    kind: session.kind
                ),
                selectionHandler: { [weak self] selectedIndex in
                    self?.selectTab(selectedIndex, inPane: paneIndex)
                },
                closeHandler: { [weak self] tabIndex in
                    self?.closeTab(tabIndex, inPane: paneIndex)
                },
                moveHandler: { [weak self] tabIndex, direction in
                    self?.moveTab(tabIndex, inPane: paneIndex, direction: direction)
                }
            )
            session.panels[paneIndex] = panel
            panel.orderFrontRegardless()
        }
    }

    private func makeTabPresentation(for window: ManagedWindow) -> PaneTabPresentation {
        PaneTabPresentation(title: window.tabTitle, ownerPID: window.ownerPID)
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
        if let session {
            refreshTabSession(session)
        } else if let bentoSession {
            refreshBentoSession(bentoSession)
        }
    }

    private func refreshTabSession(_ session: LayoutSession) {
        removeClosedWindows(from: session)

        let managedWindows = session.panes.flatMap(\.windows)
        let knownWindowIDs = Set(managedWindows.map(\.windowID))
        let candidates = windowIndexer.currentSpaceWindows().filter { candidate in
            !knownWindowIDs.contains(candidate.windowID)
                && !closingWindowIDs.contains(candidate.windowID)
                && !managedWindows.contains(where: {
                    $0.refersToSameAccessibilityWindow(as: candidate)
                })
        }

        let visibleCandidateIDs = Set(candidates.map(\.windowID))
        pendingWindowSightings = pendingWindowSightings.filter {
            visibleCandidateIDs.contains($0.key)
        }

        for candidate in candidates {
            let sightings = pendingWindowSightings[candidate.windowID, default: 0] + 1
            guard sightings >= Self.requiredNewWindowSightings else {
                pendingWindowSightings[candidate.windowID] = sightings
                continue
            }

            pendingWindowSightings.removeValue(forKey: candidate.windowID)
            addNewWindow(candidate, to: session)
        }
    }

    private func addNewWindow(_ window: ManagedWindow, to session: LayoutSession) {
        let managedWindows = session.panes.flatMap(\.windows)
        guard
            !managedWindows.contains(where: { $0.windowID == window.windowID }),
            !managedWindows.contains(where: { $0.refersToSameAccessibilityWindow(as: window) })
        else {
            return
        }

        guard let paneIndex = session.panes.indices.min(by: {
            session.panes[$0].windows.count < session.panes[$1].windows.count
        }) else { return }

        var pane = session.panes[paneIndex]
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
        let selectedWindow = pane.windows[selectedIndex]
        windowController.setAppKitFrame(
            pane.geometry.windowFrame,
            on: session.screen,
            for: selectedWindow
        )
        guard windowController.raise(selectedWindow) else {
            createOrUpdateTabBar(forPane: paneIndex, in: session)
            return
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

    private func moveTab(
        _ tabIndex: Int,
        inPane sourcePaneIndex: Int,
        direction: PaneMoveDirection
    ) {
        guard
            let session,
            let targetPaneIndex = PaneMove.destinationPaneIndex(
                from: sourcePaneIndex,
                direction: direction,
                kind: session.kind
            ),
            session.panes.indices.contains(sourcePaneIndex),
            session.panes.indices.contains(targetPaneIndex),
            session.panes[sourcePaneIndex].windows.indices.contains(tabIndex)
        else {
            return
        }

        var sourcePane = session.panes[sourcePaneIndex]
        var targetPane = session.panes[targetPaneIndex]
        let wasSelected = tabIndex == sourcePane.selectedIndex
        let window = sourcePane.windows.remove(at: tabIndex)

        if sourcePane.windows.isEmpty {
            sourcePane.selectedIndex = 0
        } else if tabIndex < sourcePane.selectedIndex {
            sourcePane.selectedIndex -= 1
        } else {
            sourcePane.selectedIndex = min(
                sourcePane.selectedIndex,
                sourcePane.windows.count - 1
            )
        }

        targetPane.windows.append(window)
        targetPane.selectedIndex = targetPane.windows.count - 1

        session.panes[sourcePaneIndex] = sourcePane
        session.panes[targetPaneIndex] = targetPane

        windowController.setAppKitFrame(
            targetPane.geometry.windowFrame,
            on: session.screen,
            for: window
        )

        if wasSelected, !sourcePane.windows.isEmpty {
            let replacement = sourcePane.windows[sourcePane.selectedIndex]
            windowController.setAppKitFrame(
                sourcePane.geometry.windowFrame,
                on: session.screen,
                for: replacement
            )
            windowController.raise(replacement)
        }

        windowController.raise(window)
        createOrUpdateTabBar(forPane: sourcePaneIndex, in: session)
        createOrUpdateTabBar(forPane: targetPaneIndex, in: session)
    }

    // MARK: - Shared helpers

    private func ensureAccessibility() -> Bool {
        if Permissions.isAccessibilityGranted {
            return true
        }

        // 先只弹系统框；不要立刻叠自定义 Alert，否则会出现「系统授权 + 好」双弹窗。
        let granted = Permissions.requestAccessibility()
        if granted || Permissions.isAccessibilityGranted {
            return true
        }

        let help = Permissions.accessibilityHelpMessage()
        Permissions.openAccessibilitySettings(promptIfNeeded: false)
        showMessage(title: help.title, message: help.message)
        return false
    }

    private func primaryScreen() -> NSScreen? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            showMessage(title: "无法开始布局", message: "RightScreen 未找到可用显示器。")
            return nil
        }
        return screen
    }

    private func manageableWindows() -> [ManagedWindow]? {
        let windows = windowIndexer.currentSpaceWindows()
        guard !windows.isEmpty else {
            showMessage(
                title: "没有可管理窗口",
                message: "请先打开至少一个普通 App 窗口；最小化、全屏和不可缩放窗口会被跳过。"
            )
            return nil
        }
        return windows
    }

    private func restoreOriginalFrames(
        _ originalFrames: [CGWindowID: CGRect],
        windows: [ManagedWindow]
    ) {
        for window in windows {
            guard
                windowController.isAlive(window),
                let originalFrame = originalFrames[window.windowID]
            else {
                continue
            }
            windowController.setAccessibilityFrame(originalFrame, for: window)
        }
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
