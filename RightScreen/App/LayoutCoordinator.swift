import AppKit

@MainActor
final class LayoutCoordinator {
    private static let fallbackReconciliationInterval: TimeInterval = 15
    private static let eventRetryDelays: [Duration] = [
        .zero,
        .milliseconds(30),
        .milliseconds(80),
        .milliseconds(180),
        .milliseconds(400)
    ]
    /// Chrome 拖出标签后会再写一遍自身尺寸，短延迟内反复提交格位 frame。
    private static let frameEnforcementDelays: [Duration] = [
        .zero,
        .milliseconds(50),
        .milliseconds(120),
        .milliseconds(250),
        .milliseconds(450),
        .milliseconds(750),
        .milliseconds(1200)
    ]

    private let windowIndexer = WindowIndexer()
    private let windowController = WindowController()
    private var reconciliationTimer: Timer?
    private var reconciliationTasks: [pid_t: Task<Void, Never>] = [:]
    private var frameEnforcementTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var closingWindowIDs = Set<CGWindowID>()
    private lazy var windowObservationService = WindowObservationService(
        onWindowCreated: { [weak self] pid in
            self?.scheduleWindowReconciliation(for: pid)
        },
        onWindowStateChanged: { [weak self] in
            self?.refreshManagedWindowState()
        },
        onFocusChanged: { [weak self] in
            self?.refreshFocusedTab()
        }
    )
    private(set) var session: LayoutSession?
    private(set) var bentoSession: BentoSession?

    var hasActiveLayout: Bool {
        session != nil || bentoSession != nil
    }

    var isBentoActive: Bool {
        bentoSession != nil
    }

    func moveFocusedTab(_ direction: PaneMoveDirection) {
        guard let session else { return }
        let focused = windowController.focusedManagedWindow(in: session.panes.flatMap(\.windows))
        guard let target = TabFocus.moveTarget(
            panes: session.panes,
            focusedWindow: focused,
            lastFocusedPaneIndex: session.lastFocusedPaneIndex
        ) else {
            return
        }

        session.lastFocusedPaneIndex = target.paneIndex
        moveTab(target.tabIndex, inPane: target.paneIndex, direction: direction)
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

        applyInitialLayout(newSession)
        createTabBars(for: newSession)
        startObservingWindows()
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

        applyBentoFrames(newSession)
        installBentoChrome(for: newSession)
        startObservingWindows()
    }

    func exitLayout() {
        windowObservationService.stop()
        reconciliationTimer?.invalidate()
        reconciliationTimer = nil
        for task in reconciliationTasks.values {
            task.cancel()
        }
        reconciliationTasks.removeAll()
        cancelAllFrameEnforcement()
        closingWindowIDs.removeAll()

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

    private func refreshBentoSession(_ session: BentoSession, discoverNewWindows: Bool) {
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

        if discoverNewWindows {
            for candidate in unmanagedWindows(
                among: windowIndexer.currentSpaceWindows(),
                comparedWith: liveWindows
            ) {
                addNewWindowToBento(candidate, session: session)
            }
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
        scheduleFrameEnforcement(for: window.windowID)
    }

    // MARK: - Tab layout (existing)

    private func applyInitialLayout(_ session: LayoutSession) {
        for (paneIndex, pane) in session.panes.enumerated() where !pane.windows.isEmpty {
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
                session.lastFocusedPaneIndex = paneIndex
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

    private func startObservingWindows() {
        windowObservationService.start()
        // 覆盖初始窗口枚举与批量安装 AXObserver 之间的短暂竞态。
        reconcileAllWindows()
        reconciliationTimer?.invalidate()
        reconciliationTimer = Timer.scheduledTimer(
            timeInterval: Self.fallbackReconciliationInterval,
            target: self,
            selector: #selector(reconcileAllWindows),
            userInfo: nil,
            repeats: true
        )
    }

    /// AX 通知偶尔会被个别 App 漏发；低频全量校准只作为容错，不再承担实时发现。
    @objc private func reconcileAllWindows() {
        if let session {
            refreshTabSession(session, discoverNewWindows: true)
        } else if let bentoSession {
            refreshBentoSession(bentoSession, discoverNewWindows: true)
        }
    }

    private func refreshManagedWindowState() {
        if let session {
            refreshTabSession(session, discoverNewWindows: false)
        } else if let bentoSession {
            refreshBentoSession(bentoSession, discoverNewWindows: false)
        }
    }

    private func refreshFocusedTab() {
        guard let session else { return }
        synchronizeTabSelectionWithSystemFocus(in: session)
    }

    private func refreshTabSession(_ session: LayoutSession, discoverNewWindows: Bool) {
        removeClosedWindows(from: session)
        synchronizeTabSelectionWithSystemFocus(in: session)
        guard discoverNewWindows else { return }

        let managedWindows = session.panes.flatMap(\.windows)
        for candidate in unmanagedWindows(
            among: windowIndexer.currentSpaceWindows(),
            comparedWith: managedWindows
        ) {
            addNewWindow(candidate, to: session)
        }
    }

    private func scheduleWindowReconciliation(for pid: pid_t) {
        reconciliationTasks[pid]?.cancel()
        reconciliationTasks[pid] = Task { @MainActor [weak self] in
            guard let self else { return }

            for delay in Self.eventRetryDelays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, self.hasActiveLayout else { return }
                if self.reconcileNewWindows(ownerPID: pid) > 0 {
                    break
                }
            }
            self.reconciliationTasks[pid] = nil
        }
    }

    @discardableResult
    private func reconcileNewWindows(ownerPID: pid_t) -> Int {
        let candidates = windowIndexer.currentSpaceWindows(ownerPID: ownerPID)

        if let session {
            let managedWindows = session.panes.flatMap(\.windows)
            let newWindows = unmanagedWindows(among: candidates, comparedWith: managedWindows)
            for window in newWindows {
                addNewWindow(window, to: session)
            }
            return newWindows.count
        }

        if let bentoSession {
            let managedWindows = BentoEngine.leafValues(bentoSession.tree)
            let newWindows = unmanagedWindows(among: candidates, comparedWith: managedWindows)
            for window in newWindows {
                addNewWindowToBento(window, session: bentoSession)
            }
            return newWindows.count
        }

        return 0
    }

    private func unmanagedWindows(
        among candidates: [ManagedWindow],
        comparedWith managedWindows: [ManagedWindow]
    ) -> [ManagedWindow] {
        let knownWindowIDs = Set(managedWindows.map(\.windowID))
        return candidates.filter { candidate in
            !knownWindowIDs.contains(candidate.windowID)
                && !closingWindowIDs.contains(candidate.windowID)
                && !managedWindows.contains(where: {
                    $0.refersToSameAccessibilityWindow(as: candidate)
                })
        }
    }

    private func synchronizeTabSelectionWithSystemFocus(in session: LayoutSession) {
        let managedWindows = session.panes.flatMap(\.windows)
        guard let focusedWindow = windowController.focusedManagedWindow(in: managedWindows) else {
            return
        }

        for paneIndex in session.panes.indices {
            let pane = session.panes[paneIndex]
            guard let focusedIndex = pane.windows.firstIndex(where: {
                $0.refersToSameAccessibilityWindow(as: focusedWindow)
            }) else {
                continue
            }
            session.lastFocusedPaneIndex = paneIndex
            session.panes[paneIndex].recordActivation(of: focusedWindow)
            guard pane.selectedIndex != focusedIndex else { return }

            session.panes[paneIndex].selectedIndex = focusedIndex
            createOrUpdateTabBar(forPane: paneIndex, in: session)
            return
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

        let latestFrame = AXHelpers.frame(of: window.element) ?? window.frame
        let appKitFrame = ScreenFrameConversion.flippingY(
            latestFrame,
            relativeTo: session.screen.frame
        )
        guard let paneIndex = NewWindowPlacement.paneIndex(
            windowFrame: appKitFrame,
            paneFrames: session.panes.map(\.geometry.paneFrame),
            lastFocusedPaneIndex: session.lastFocusedPaneIndex,
            paneWindowCounts: session.panes.map(\.windows.count)
        ) else { return }

        var pane = session.panes[paneIndex]
        session.originalFrames[window.windowID] = latestFrame
        session.autoJoinedWindowIDs.insert(window.windowID)
        pane.windows.append(window)
        pane.selectWindow(at: pane.windows.count - 1)
        session.panes[paneIndex] = pane

        windowController.raise(window)
        session.lastFocusedPaneIndex = paneIndex
        createOrUpdateTabBar(forPane: paneIndex, in: session)
        scheduleFrameEnforcement(for: window.windowID)
    }

    private func removeClosedWindows(from session: LayoutSession) {
        for paneIndex in session.panes.indices {
            var pane = session.panes[paneIndex]
            let selectedID = pane.windows.indices.contains(pane.selectedIndex)
                ? pane.windows[pane.selectedIndex].windowID
                : nil
            let liveWindows = pane.windows.filter(windowController.isAlive)
            guard liveWindows.count != pane.windows.count else { continue }

            let closedIDs = Set(pane.windows.map(\.windowID)).subtracting(liveWindows.map(\.windowID))
            session.autoJoinedWindowIDs.subtract(closedIDs)
            for windowID in closedIDs {
                cancelFrameEnforcement(for: windowID)
            }
            pane.windows = liveWindows
            pane.activationHistory.removeAll { id in
                !liveWindows.contains(where: { $0.windowID == id })
            }
            if let selectedID, let retainedIndex = liveWindows.firstIndex(where: { $0.windowID == selectedID }) {
                pane.selectedIndex = retainedIndex
            } else {
                pane.selectedIndex = PaneTabHistory.selectedIndex(
                    remainingIDs: liveWindows.map(\.windowID),
                    history: pane.activationHistory,
                    removedIndex: pane.selectedIndex
                )
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
        session.autoJoinedWindowIDs.remove(selectedWindow.windowID)
        session.panes[paneIndex].selectWindow(at: selectedIndex)
        session.lastFocusedPaneIndex = paneIndex
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
        cancelFrameEnforcement(for: window.windowID)
        session.originalFrames.removeValue(forKey: window.windowID)
        session.autoJoinedWindowIDs.remove(window.windowID)
        let wasSelected = tabIndex == pane.selectedIndex
        pane.windows.remove(at: tabIndex)
        pane.selectAfterRemoving(windowID: window.windowID, at: tabIndex)
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
        let restoreSourceFocus = session.autoJoinedWindowIDs.contains(
            sourcePane.windows[tabIndex].windowID
        )
        let window = sourcePane.windows.remove(at: tabIndex)
        session.autoJoinedWindowIDs.remove(window.windowID)
        sourcePane.selectAfterRemoving(windowID: window.windowID, at: tabIndex)

        targetPane.windows.append(window)
        targetPane.selectWindow(at: targetPane.windows.count - 1)

        session.panes[sourcePaneIndex] = sourcePane
        session.panes[targetPaneIndex] = targetPane

        windowController.setAppKitFrame(
            targetPane.geometry.windowFrame,
            on: session.screen,
            for: window
        )
        windowController.raise(window)

        if !sourcePane.windows.isEmpty {
            let replacement = sourcePane.windows[sourcePane.selectedIndex]
            windowController.setAppKitFrame(
                sourcePane.geometry.windowFrame,
                on: session.screen,
                for: replacement
            )
            windowController.raise(replacement)
            if restoreSourceFocus {
                session.lastFocusedPaneIndex = sourcePaneIndex
                createOrUpdateTabBar(forPane: sourcePaneIndex, in: session)
                createOrUpdateTabBar(forPane: targetPaneIndex, in: session)
                return
            }
        }

        windowController.raise(window)
        session.lastFocusedPaneIndex = targetPaneIndex
        createOrUpdateTabBar(forPane: sourcePaneIndex, in: session)
        createOrUpdateTabBar(forPane: targetPaneIndex, in: session)
    }

    private func scheduleFrameEnforcement(for windowID: CGWindowID) {
        frameEnforcementTasks[windowID]?.cancel()
        frameEnforcementTasks[windowID] = Task { @MainActor [weak self] in
            guard let self else { return }

            for delay in Self.frameEnforcementDelays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, self.hasActiveLayout else { return }
                if self.enforceManagedWindowFrame(windowID: windowID) {
                    break
                }
            }
            self.frameEnforcementTasks[windowID] = nil
        }
    }

    /// 把窗口重新写入当前所属格位。已贴合格位则返回 true，停止重试。
    @discardableResult
    private func enforceManagedWindowFrame(windowID: CGWindowID) -> Bool {
        if let session {
            for pane in session.panes {
                guard let window = pane.windows.first(where: { $0.windowID == windowID }) else {
                    continue
                }
                let expected = pane.geometry.windowFrame
                windowController.setAppKitFrame(expected, on: session.screen, for: window)
                let expectedAX = ScreenFrameConversion.flippingY(
                    expected,
                    relativeTo: session.screen.frame
                )
                return windowController.frameMatches(window, accessibilityFrame: expectedAX)
            }
            return true
        }

        if let bentoSession {
            guard let leaf = bentoSession.leafLayouts().first(where: {
                $0.value.windowID == windowID
            }) else {
                return true
            }
            windowController.setAppKitFrame(leaf.frame, on: bentoSession.screen, for: leaf.value)
            let expectedAX = ScreenFrameConversion.flippingY(
                leaf.frame,
                relativeTo: bentoSession.screen.frame
            )
            return windowController.frameMatches(leaf.value, accessibilityFrame: expectedAX)
        }

        return true
    }

    private func cancelFrameEnforcement(for windowID: CGWindowID) {
        frameEnforcementTasks[windowID]?.cancel()
        frameEnforcementTasks[windowID] = nil
    }

    private func cancelAllFrameEnforcement() {
        for task in frameEnforcementTasks.values {
            task.cancel()
        }
        frameEnforcementTasks.removeAll()
    }

    // MARK: - Shared helpers

    private func ensureAccessibility() -> Bool {
        if let issue = Permissions.signingIssue {
            let help = Permissions.accessibilityHelpMessage(signingIssue: issue)
            showMessage(title: help.title, message: help.message)
            return false
        }

        if Permissions.isAccessibilityGranted {
            return true
        }

        // 系统提示本身已包含“打开系统设置”，这里不再叠加自定义 Alert。
        let granted = Permissions.requestAccessibility()
        if granted || Permissions.isAccessibilityGranted {
            return true
        }
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
