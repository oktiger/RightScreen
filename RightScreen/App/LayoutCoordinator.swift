import AppKit

@MainActor
final class LayoutCoordinator {
    private struct PendingPaneDrop: Equatable {
        let id = UUID()
        let paneIndex: Int
    }

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
    private static let settlePollInterval: Duration = .milliseconds(50)
    private static let settleTimeout: Duration = .seconds(8)
    private static let dropAdoptionDelays: [Duration] = [
        .zero,
        .milliseconds(50),
        .milliseconds(120),
        .milliseconds(250),
        .milliseconds(450),
        .milliseconds(800),
        .milliseconds(1300)
    ]

    private let windowIndexer = WindowIndexer()
    private let windowController = WindowController()
    private let dropTracker = PaneDropTracker()
    private var reconciliationTimer: Timer?
    private var reconciliationTasks: [pid_t: Task<Void, Never>] = [:]
    private var adoptionTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var frameEnforcementTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var closeTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var dropAdoptionTask: Task<Void, Never>?
    private var pendingPaneDrop: PendingPaneDrop?
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
        startDropTracking(for: newSession)
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
        cancelAllAdoptions()
        cancelAllFrameEnforcement()
        for task in closeTasks.values {
            task.cancel()
        }
        closeTasks.removeAll()
        cancelPendingDropAdoption()
        dropTracker.stop()
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

        releaseNativeFullScreenWindows(from: session)
        guard bentoSession != nil else { return }

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
                scheduleSettledAdoption(for: candidate)
            }
        }
    }

    private func addNewWindowToBento(_ window: ManagedWindow, session: BentoSession) {
        guard !windowController.isNativeFullScreen(window) else { return }

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

    private func createOrUpdateTabBar(
        forPane paneIndex: Int,
        in session: LayoutSession,
        bringToFront: Bool = true
    ) {
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
            if bringToFront {
                panel.orderFrontRegardless()
            }
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
            if bringToFront {
                panel.orderFrontRegardless()
            }
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
        if let session {
            releaseNativeFullScreenWindows(from: session)
            guard self.session != nil else { return }
            synchronizeTabSelectionWithSystemFocus(in: session)
        } else if let bentoSession {
            releaseNativeFullScreenWindows(from: bentoSession)
        }
    }

    private func refreshTabSession(_ session: LayoutSession, discoverNewWindows: Bool) {
        releaseNativeFullScreenWindows(from: session)
        guard self.session != nil else { return }
        removeClosedWindows(from: session)
        synchronizeTabSelectionWithSystemFocus(in: session)
        guard discoverNewWindows else { return }

        let managedWindows = session.panes.flatMap(\.windows)
        for candidate in unmanagedWindows(
            among: windowIndexer.currentSpaceWindows(),
            comparedWith: managedWindows
        ) {
            scheduleSettledAdoption(for: candidate)
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
                scheduleSettledAdoption(for: window)
            }
            return newWindows.count
        }

        if let bentoSession {
            let managedWindows = BentoEngine.leafValues(bentoSession.tree)
            let newWindows = unmanagedWindows(among: candidates, comparedWith: managedWindows)
            for window in newWindows {
                scheduleSettledAdoption(for: window)
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
        guard !windowController.isNativeFullScreen(window) else { return }

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
        let paneIndex: Int
        if let pendingPaneDrop, session.panes.indices.contains(pendingPaneDrop.paneIndex) {
            paneIndex = pendingPaneDrop.paneIndex
        } else if let placed = NewWindowPlacement.paneIndex(
            windowFrame: appKitFrame,
            paneFrames: session.panes.map(\.geometry.paneFrame),
            lastFocusedPaneIndex: session.lastFocusedPaneIndex,
            paneWindowCounts: session.panes.map(\.windows.count)
        ) {
            paneIndex = placed
        } else {
            return
        }

        var pane = session.panes[paneIndex]
        session.originalFrames[window.windowID] = latestFrame
        session.autoJoinedWindowIDs.insert(window.windowID)
        pane.windows.append(window)
        pane.selectWindow(at: pane.windows.count - 1)
        session.panes[paneIndex] = pane

        windowController.setAppKitFrame(pane.geometry.windowFrame, on: session.screen, for: window)
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
            closingWindowIDs.subtract(closedIDs)
            for windowID in closedIDs {
                cancelFrameEnforcement(for: windowID)
                session.originalFrames.removeValue(forKey: windowID)
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

        let window = session.panes[paneIndex].windows[tabIndex]
        guard closeTasks[window.windowID] == nil else { return }

        closeTasks[window.windowID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.windowController.close(window)
            guard !Task.isCancelled else { return }
            self.closeTasks[window.windowID] = nil
            self.handleCloseResult(result, for: window)
        }
    }

    private func handleCloseResult(_ result: WindowCloseResult, for window: ManagedWindow) {
        switch result {
        case .requested:
            // AXPress only means macOS accepted the close request. A document with
            // unsaved changes may still show a confirmation sheet, so retain its Tab
            // until the window is actually destroyed.
            closingWindowIDs.insert(window.windowID)
            closeTasks[window.windowID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                if let session = self.session {
                    self.removeClosedWindows(from: session)
                }
                if self.windowController.isAlive(window) {
                    self.closingWindowIDs.remove(window.windowID)
                }
                self.closeTasks[window.windowID] = nil
            }
        case .windowUnavailable:
            if let session {
                removeClosedWindows(from: session)
            }
        case .blockedByModalDialog:
            showMessage(
                title: "请先处理对话框",
                message: "“\(window.appName)”当前有一个打开、保存或确认对话框正在等待处理。请先完成或取消该对话框，再关闭窗口；窗口布局管理不受影响。"
            )
        case .temporarilyUnavailable:
            showMessage(
                title: "暂时无法关闭窗口",
                message: "macOS 辅助功能服务暂时没有响应。RightScreen 已自动重试，请稍后再试。"
            )
        case .accessibilityPermissionRequired:
            showMessage(
                title: "需要辅助功能权限",
                message: "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 RightScreen，然后重试。"
            )
        case .unsupported:
            showMessage(
                title: "这个窗口不提供关闭控制",
                message: "RightScreen 仍可管理它的位置和大小，但该窗口没有提供系统关闭按钮。为避免误关窗口或退出整个 App，请使用该 App 自己的关闭按钮。"
            )
        case .failed:
            showMessage(
                title: "无法关闭窗口",
                message: "macOS 拒绝了这次关闭请求。请先切换到该窗口并处理其中的提示，然后重试。"
            )
        }
    }

    private func moveTab(
        _ tabIndex: Int,
        inPane sourcePaneIndex: Int,
        direction: PaneMoveDirection
    ) {
        guard let session else { return }
        if session.kind == .fullScreen {
            expandFullScreenToSplit2(
                movingTab: tabIndex,
                inPane: sourcePaneIndex,
                direction: direction,
                in: session
            )
            return
        }

        guard
            let targetPaneIndex = PaneMove.destinationPaneIndex(
                from: sourcePaneIndex,
                direction: direction,
                kind: session.kind
            )
        else {
            return
        }

        moveTab(tabIndex, fromPane: sourcePaneIndex, toPane: targetPaneIndex, in: session)
    }

    /// 全屏 1 格时左右快捷键切到左右二分：当前 Tab 落到对应侧，其余窗口留在对侧。
    private func expandFullScreenToSplit2(
        movingTab tabIndex: Int,
        inPane sourcePaneIndex: Int,
        direction: PaneMoveDirection,
        in session: LayoutSession
    ) {
        guard
            sourcePaneIndex == 0,
            session.panes.indices.contains(0)
        else {
            return
        }

        let sourcePane = session.panes[0]
        guard
            let expansion = PaneMove.expandFullScreenToSplit2(
                windows: sourcePane.windows,
                movingIndex: tabIndex,
                direction: direction
            )
        else {
            return
        }

        let movedWindow = sourcePane.windows[tabIndex]
        let remainingHistory = PaneTabHistory.removing(
            movedWindow.windowID,
            from: sourcePane.activationHistory
        )
        let remainingIDs = expansion.windowsByPane[1 - expansion.focusedPaneIndex].map(\.windowID)
        let remainingSelected = PaneTabHistory.selectedIndex(
            remainingIDs: remainingIDs,
            history: remainingHistory,
            removedIndex: tabIndex
        )
        let geometries = LayoutEngine.geometries(for: .split2, in: session.screen.visibleFrame)

        for panel in session.panels.compactMap({ $0 }) {
            panel.orderOut(nil)
            panel.close()
        }

        session.kind = .split2
        session.panes = geometries.enumerated().map { paneIndex, geometry in
            let windows = expansion.windowsByPane[paneIndex]
            let isFocusedPane = paneIndex == expansion.focusedPaneIndex
            return PaneState(
                geometry: geometry,
                windows: windows,
                selectedIndex: isFocusedPane ? 0 : remainingSelected,
                activationHistory: isFocusedPane
                    ? (windows.first.map { [$0.windowID] } ?? [])
                    : remainingHistory
            )
        }
        session.panels = Array(repeating: nil, count: session.panes.count)
        session.lastFocusedPaneIndex = expansion.focusedPaneIndex

        applyInitialLayout(session)
        if let focused = session.panes[expansion.focusedPaneIndex].windows.first {
            windowController.raise(focused)
        }
        createTabBars(for: session)
        dropTracker.updatePaneFrames(session.panes.map(\.geometry.paneFrame))
        for window in session.panes.flatMap(\.windows) {
            scheduleFrameEnforcement(for: window.windowID)
        }
    }

    /// Tab 栏箭头和跨格拖放共用同一份换格语义，保证 MRU、焦点恢复与窗口 frame 一致。
    private func moveTab(
        _ tabIndex: Int,
        fromPane sourcePaneIndex: Int,
        toPane targetPaneIndex: Int,
        in session: LayoutSession
    ) {
        guard
            session.panes.indices.contains(sourcePaneIndex),
            session.panes.indices.contains(targetPaneIndex),
            sourcePaneIndex != targetPaneIndex,
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
        scheduleFrameEnforcement(for: window.windowID)

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

    private func startDropTracking(for session: LayoutSession) {
        dropTracker.onDropBetweenPanes = { [weak self] destination in
            self?.handleDrop(between: destination)
        }
        dropTracker.start(paneFrames: session.panes.map(\.geometry.paneFrame))
    }

    /// 已接管窗口直接换格；Chrome 刚拖出的新窗口则交给短时发现流程并入目标格。
    private func handleDrop(between destination: PaneDropDestination) {
        guard
            let session,
            session.panes.indices.contains(destination.sourcePaneIndex),
            session.panes.indices.contains(destination.targetPaneIndex)
        else {
            return
        }

        cancelPendingDropAdoption()
        if reassignDraggedManagedWindow(between: destination, in: session) {
            return
        }
        adoptDroppedWindows(intoPane: destination.targetPaneIndex)
    }

    /// 文本、链接等普通拖放不会改变窗口 frame；只有 frame 离开所属格位的受管窗口才允许换格。
    private func reassignDraggedManagedWindow(
        between destination: PaneDropDestination,
        in session: LayoutSession
    ) -> Bool {
        let managedWindows = session.panes.flatMap(\.windows)
        var candidates: [ManagedWindow] = []

        if let focused = windowController.focusedManagedWindow(in: managedWindows) {
            candidates.append(focused)
        }
        let sourcePane = session.panes[destination.sourcePaneIndex]
        if sourcePane.windows.indices.contains(sourcePane.selectedIndex) {
            let selected = sourcePane.windows[sourcePane.selectedIndex]
            if !candidates.contains(where: { $0.refersToSameAccessibilityWindow(as: selected) }) {
                candidates.append(selected)
            }
        }

        for candidate in candidates {
            guard let membership = managedWindowMembership(candidate, in: session) else {
                continue
            }
            guard
                membership.paneIndex == destination.sourcePaneIndex
                    || membership.paneIndex == destination.targetPaneIndex
            else {
                continue
            }
            let expectedAXFrame = ScreenFrameConversion.flippingY(
                session.panes[membership.paneIndex].geometry.windowFrame,
                relativeTo: session.screen.frame
            )
            guard
                let actualAXFrame = AXHelpers.frame(of: candidate.element),
                !PaneFrameFit.matches(actualAXFrame, expected: expectedAXFrame)
            else {
                continue
            }

            if membership.paneIndex == destination.targetPaneIndex {
                windowController.setAppKitFrame(
                    session.panes[membership.paneIndex].geometry.windowFrame,
                    on: session.screen,
                    for: candidate
                )
                windowController.raise(candidate)
                scheduleFrameEnforcement(for: candidate.windowID)
            } else {
                moveTab(
                    membership.tabIndex,
                    fromPane: membership.paneIndex,
                    toPane: destination.targetPaneIndex,
                    in: session
                )
            }
            return true
        }
        return false
    }

    private func managedWindowMembership(
        _ window: ManagedWindow,
        in session: LayoutSession
    ) -> (paneIndex: Int, tabIndex: Int)? {
        for paneIndex in session.panes.indices {
            if let tabIndex = session.panes[paneIndex].windows.firstIndex(where: {
                $0.refersToSameAccessibilityWindow(as: window)
            }) {
                return (paneIndex, tabIndex)
            }
        }
        return nil
    }

    /// 松手时格位已由蒙版确定；此后短时间内出现的新窗口一律进该格并铺满。
    private func adoptDroppedWindows(intoPane paneIndex: Int) {
        guard let session, session.panes.indices.contains(paneIndex) else { return }

        let pendingDrop = PendingPaneDrop(paneIndex: paneIndex)
        pendingPaneDrop = pendingDrop
        dropAdoptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingPaneDrop == pendingDrop {
                    self.pendingPaneDrop = nil
                    self.dropAdoptionTask = nil
                }
            }

            for delay in Self.dropAdoptionDelays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, let session = self.session else { return }

                let managedWindows = session.panes.flatMap(\.windows)
                let newcomers = self.unmanagedWindows(
                    among: self.windowIndexer.currentSpaceWindows(),
                    comparedWith: managedWindows
                )
                for window in newcomers {
                    self.adoptionTasks[window.windowID]?.cancel()
                    self.adoptionTasks[window.windowID] = nil
                    self.addNewWindow(window, to: session)
                }
                if !newcomers.isEmpty {
                    try? await Task.sleep(for: .milliseconds(800))
                    return
                }
            }
        }
    }

    private func scheduleSettledAdoption(for window: ManagedWindow) {
        let windowID = window.windowID
        guard adoptionTasks[windowID] == nil, frameEnforcementTasks[windowID] == nil else {
            return
        }

        adoptionTasks[windowID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.adoptionTasks[windowID] = nil }

            var lastFrame = AXHelpers.frame(of: window.element) ?? window.frame
            var stableCount = 0
            let deadline = ContinuousClock.now + Self.settleTimeout

            while !Task.isCancelled, self.hasActiveLayout, ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.settlePollInterval)
                guard !Task.isCancelled, self.hasActiveLayout else { return }
                guard self.windowController.isAlive(window) else { return }

                let currentFrame = AXHelpers.frame(of: window.element) ?? lastFrame
                if self.dropTracker.isTrackingMouseDrag {
                    stableCount = 0
                    lastFrame = currentFrame
                    continue
                }
                stableCount = WindowSettle.nextStableCount(
                    previous: lastFrame,
                    current: currentFrame,
                    stableCount: stableCount
                )
                lastFrame = currentFrame
                if WindowSettle.isSettled(stableCount) {
                    break
                }
            }

            guard !Task.isCancelled, self.hasActiveLayout, self.windowController.isAlive(window) else {
                return
            }
            guard !self.windowController.isNativeFullScreen(window) else { return }

            if let session = self.session {
                self.addNewWindow(window, to: session)
            } else if let bentoSession = self.bentoSession {
                self.addNewWindowToBento(window, session: bentoSession)
            }
        }
    }

    private func cancelAllAdoptions() {
        for task in adoptionTasks.values {
            task.cancel()
        }
        adoptionTasks.removeAll()
    }

    private func cancelPendingDropAdoption() {
        dropAdoptionTask?.cancel()
        dropAdoptionTask = nil
        pendingPaneDrop = nil
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
                if windowController.isNativeFullScreen(window) {
                    return true
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
            if windowController.isNativeFullScreen(leaf.value) {
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

    /// 原生全屏会开新 Space。接管中的窗口一旦进入全屏就立刻放手，
    /// 且不要 raise / 改 frame，否则会打断过渡并弹出 Mission Control。
    private func releaseNativeFullScreenWindows(from session: LayoutSession) {
        let displays = NativeFullScreen.displayBounds()
        var didRelease = false

        for paneIndex in session.panes.indices {
            var pane = session.panes[paneIndex]
            let remaining = pane.windows.filter {
                !windowController.isNativeFullScreen($0, displays: displays)
            }
            guard remaining.count != pane.windows.count else { continue }

            didRelease = true
            let released = pane.windows.filter { window in
                !remaining.contains(where: { $0.windowID == window.windowID })
            }
            forgetReleasedWindows(released, originalFrames: &session.originalFrames)
            session.autoJoinedWindowIDs.subtract(Set(released.map(\.windowID)))

            let selectedID = pane.windows.indices.contains(pane.selectedIndex)
                ? pane.windows[pane.selectedIndex].windowID
                : nil
            pane.windows = remaining
            pane.activationHistory.removeAll { id in
                !remaining.contains(where: { $0.windowID == id })
            }
            if let selectedID, let retainedIndex = remaining.firstIndex(where: { $0.windowID == selectedID }) {
                pane.selectedIndex = retainedIndex
            } else {
                pane.selectedIndex = PaneTabHistory.selectedIndex(
                    remainingIDs: remaining.map(\.windowID),
                    history: pane.activationHistory,
                    removedIndex: pane.selectedIndex
                )
            }
            session.panes[paneIndex] = pane
            createOrUpdateTabBar(forPane: paneIndex, in: session, bringToFront: false)
        }

        if didRelease, session.panes.allSatisfy(\.windows.isEmpty) {
            exitLayout()
        }
    }

    private func releaseNativeFullScreenWindows(from session: BentoSession) {
        let displays = NativeFullScreen.displayBounds()
        let values = BentoEngine.leafValues(session.tree)
        let remaining = values.filter {
            !windowController.isNativeFullScreen($0, displays: displays)
        }
        guard remaining.count != values.count else { return }

        let released = values.filter { window in
            !remaining.contains(where: { $0.windowID == window.windowID })
        }
        forgetReleasedWindows(released, originalFrames: &session.originalFrames)

        if remaining.isEmpty {
            exitLayout()
            return
        }
        guard let rebuilt = BentoEngine.buildTree(remaining) else { return }
        session.tree = rebuilt
        session.dividerController?.update(dividers: session.dividerLayouts())
    }

    private func forgetReleasedWindows(
        _ windows: [ManagedWindow],
        originalFrames: inout [CGWindowID: CGRect]
    ) {
        for window in windows {
            cancelFrameEnforcement(for: window.windowID)
            adoptionTasks[window.windowID]?.cancel()
            adoptionTasks[window.windowID] = nil
            originalFrames.removeValue(forKey: window.windowID)
        }
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
                !windowController.isNativeFullScreen(window),
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
