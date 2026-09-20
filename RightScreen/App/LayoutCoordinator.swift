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
    /// raise 之后 WindowServer 与各 App 的激活通知回声窗口。
    private static let stackRestackEchoWindow: TimeInterval = 0.4
    /// 激活通知早于叠放生效时的补查延迟。
    private static let stackRecheckDelay: Duration = .milliseconds(120)
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
    /// 插拔显示器会连发多次通知，坐标空间也要过一会儿才稳定。
    private static let screenRelayoutDelays: [Duration] = [
        .zero,
        .milliseconds(80),
        .milliseconds(250),
        .milliseconds(700)
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
    private var screenRelayoutTask: Task<Void, Never>?
    private var pendingPaneDrop: PendingPaneDrop?
    private var closingWindowIDs = Set<CGWindowID>()
    /// 已确认关掉、但 AX 元素还没消失的窗口。
    ///
    /// Mac Catalyst App 关窗之后 AXUIElement 仍然可读，只靠 `isAlive` 会让 Tab 永远留着，
    /// 后续的 raise 还会把这个 App 重新激活、让它再开一个窗口，看起来就是「关不掉」。
    private var destroyedWindowIDs = Set<CGWindowID>()
    /// 盖住同应用兄弟窗口时会触发焦点通知，忽略这些回声以免再次 raise。
    private var isPreservingWindowStack = false
    /// raise 引发的激活通知是异步回来的，同步标志拦不住；这里用一小段静默期兜住。
    private var stackRestackSuppressedUntil: Date?
    private var stackRecheckTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
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
        destroyedWindowIDs.removeAll()

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
        destroyedWindowIDs.removeAll()

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
        stackRecheckTask?.cancel()
        stackRecheckTask = nil
        stackRestackSuppressedUntil = nil
        screenRelayoutTask?.cancel()
        screenRelayoutTask = nil
        dropTracker.stop()
        closingWindowIDs.removeAll()
        destroyedWindowIDs.removeAll()

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
        let leaves = session.leafLayouts()
        let onScreenWindowIDs = windowController.onScreenWindowIDs()
        for leaf in leaves {
            windowController.setAppKitFrame(leaf.frame, for: leaf.value)
            windowController.raise(leaf.value, withOnScreenWindowIDs: onScreenWindowIDs)
        }
        if let focused = leaves.last?.value {
            preserveVisibleWindowStack(keepingFront: focused)
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
        // 网格模式同样要认出「AX 元素还在、窗口已经没了」的 Mac Catalyst 窗口，
        // 否则它会一直占着一个格子，而每次重排都会重新前置它、把它唤回来。
        markWindowsClosedOutsideRightScreen(among: previousValues)
        let liveWindows = previousValues.filter { window in
            windowController.isAlive(window) && !destroyedWindowIDs.contains(window.windowID)
        }
        if liveWindows.count != previousValues.count {
            let closed = previousValues.filter { window in
                !liveWindows.contains(where: { $0.windowID == window.windowID })
            }
            let closedIDs = Set(closed.map(\.windowID))
            closingWindowIDs.subtract(closedIDs)
            // 窗口 ID 会被系统回收再利用，移出布局后必须立刻忘记。
            destroyedWindowIDs.subtract(closedIDs)
            forgetReleasedWindows(closed, originalFrames: &session.originalFrames)

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
        guard windowController.canActivate(window) else { return }

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
                windowController.setAppKitFrame(pane.geometry.windowFrame, for: window)
            }

            if pane.windows.indices.contains(pane.selectedIndex) {
                let selectedWindow = pane.windows[pane.selectedIndex]
                windowController.raise(selectedWindow)
                session.lastFocusedPaneIndex = paneIndex
            }
        }

        if let focusedPane = session.panes.last(where: {
            $0.windows.indices.contains($0.selectedIndex)
        }) {
            preserveVisibleWindowStack(keepingFront: focusedPane.windows[focusedPane.selectedIndex])
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
                selectedIndex: pane.selectedIndex,
                frame: pane.geometry.tabBarFrame
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
        if isPreservingWindowStack { return }

        if let session {
            releaseNativeFullScreenWindows(from: session)
            guard self.session != nil else { return }
            synchronizeTabSelectionWithSystemFocus(in: session)
        } else if let bentoSession {
            releaseNativeFullScreenWindows(from: bentoSession)
            guard self.bentoSession != nil else { return }
            let managedWindows = BentoEngine.leafValues(bentoSession.tree)
            if let focused = windowController.focusedManagedWindow(in: managedWindows) {
                preserveVisibleWindowStack(keepingFront: focused)
            }
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
            if pane.selectedIndex != focusedIndex {
                session.panes[paneIndex].selectedIndex = focusedIndex
                createOrUpdateTabBar(forPane: paneIndex, in: session)
            }
            preserveVisibleWindowStack(keepingFront: focusedWindow)
            return
        }
    }

    private func raisePreservingOtherPanes(_ window: ManagedWindow) {
        windowController.raise(window)
        // 用户显式操作：叠放结果尚未反映到 WindowServer，直接按格位重排一次。
        restackVisibleWindows(keepingFront: window, forced: true)
    }

    /// 焦点事件路径：只在确实被同应用兄弟窗口盖住时才重排。
    private func preserveVisibleWindowStack(keepingFront window: ManagedWindow) {
        restackVisibleWindows(keepingFront: window, forced: false, allowRecheck: true)
    }

    /// 同应用激活时会把兄弟窗口一起前置。把其他格当前可见的、不同进程窗口
    /// 用「只前置当前窗口」再抬一次盖回去，最后再把焦点还给目标窗口。
    ///
    /// `forced == false` 时先读 CG 真实叠放顺序：没有遮挡就一次 raise 都不做。
    /// 每次 raise 都会切换前台进程并回传激活通知，无条件重排会让通知指数级放大，
    /// 表现就是 2 格 / 3 格布局下屏幕持续闪烁。
    private func restackVisibleWindows(
        keepingFront window: ManagedWindow,
        forced: Bool,
        allowRecheck: Bool = false
    ) {
        guard !isPreservingWindowStack else { return }
        if !forced, let until = stackRestackSuppressedUntil, Date() < until { return }

        // 一次读好屏幕窗口名单，后面所有 raise 复用同一份快照：
        // 既省掉逐个窗口重复读取，也保证不会前置一个已经关掉的窗口。
        let onScreenWindowIDs = windowController.onScreenWindowIDs()
        guard windowController.canActivate(window, withOnScreenWindowIDs: onScreenWindowIDs) else {
            return
        }

        let visibleWindows = visibleManagedWindows().filter {
            windowController.canActivate($0, withOnScreenWindowIDs: onScreenWindowIDs)
        }
        let covering: [ManagedWindow]
        if forced {
            covering = WindowStacking.coveringWindows(
                keepingFront: window,
                visibleWindows: visibleWindows
            )
        } else {
            covering = WindowStacking.windowsNeedingRestack(
                keepingFront: window,
                visibleWindows: visibleWindows,
                stack: windowIndexer.onScreenWindowStack()
            )
            guard !covering.isEmpty else {
                // WindowServer 的叠放更新晚于激活通知，稍后再看一眼；只补这一次。
                if allowRecheck {
                    scheduleStackRecheck(keepingFront: window)
                }
                return
            }
        }

        isPreservingWindowStack = true
        defer { isPreservingWindowStack = false }

        for other in covering {
            windowController.raise(other, withOnScreenWindowIDs: onScreenWindowIDs)
        }
        windowController.raise(window, withOnScreenWindowIDs: onScreenWindowIDs)

        if let session {
            for panel in session.panels.compactMap({ $0 }) {
                panel.orderFrontRegardless()
            }
        }

        // 忽略这批 raise 自己引发的激活回声，避免再次进入重排。
        stackRestackSuppressedUntil = Date().addingTimeInterval(Self.stackRestackEchoWindow)
    }

    private func scheduleStackRecheck(keepingFront window: ManagedWindow) {
        stackRecheckTask?.cancel()
        stackRecheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.stackRecheckDelay)
            guard let self, !Task.isCancelled, self.hasActiveLayout else { return }
            self.stackRecheckTask = nil
            self.restackVisibleWindows(keepingFront: window, forced: false)
        }
    }

    /// 各格（或网格各叶）当前显示的窗口。已确认关掉的窗口不算「可见」，
    /// 否则重排会把它重新前置，等于替用户点了一次 Dock 图标。
    private func visibleManagedWindows() -> [ManagedWindow] {
        let windows: [ManagedWindow]
        if let session {
            windows = session.panes.compactMap { pane in
                pane.windows.indices.contains(pane.selectedIndex)
                    ? pane.windows[pane.selectedIndex]
                    : nil
            }
        } else if let bentoSession {
            windows = BentoEngine.leafValues(bentoSession.tree)
        } else {
            return []
        }
        return windows.filter { !destroyedWindowIDs.contains($0.windowID) }
    }

    private func addNewWindow(_ window: ManagedWindow, to session: LayoutSession) {
        guard !windowController.isNativeFullScreen(window) else { return }
        // 发现到并入之间窗口可能已经被关掉。并入会立刻前置它，
        // 而前置一个已经没了的窗口会把它所属的 App 重新唤起来。
        guard windowController.canActivate(window) else { return }

        let managedWindows = session.panes.flatMap(\.windows)
        guard
            !managedWindows.contains(where: { $0.windowID == window.windowID }),
            !managedWindows.contains(where: { $0.refersToSameAccessibilityWindow(as: window) })
        else {
            return
        }

        let latestFrame = AXHelpers.frame(of: window.element) ?? window.frame
        let appKitFrame = ScreenIdentity.convertFrame(latestFrame)
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

        windowController.setAppKitFrame(pane.geometry.windowFrame, for: window)
        raisePreservingOtherPanes(window)
        session.lastFocusedPaneIndex = paneIndex
        createOrUpdateTabBar(forPane: paneIndex, in: session)
        scheduleFrameEnforcement(for: window.windowID)
    }

    /// 认出「用户自己点关闭按钮关掉、但 AX 元素还赖着不走」的窗口。
    ///
    /// Mac Catalyst App 关窗后 AXUIElement 依旧可读，Tab 会一直留在窗格里。
    /// 离开屏幕窗口名单也可能只是切到了别的桌面，所以要求至少还有一个受管窗口
    /// 留在当前 Space 上：那说明布局所在的桌面没变，消失的窗口就是真的被关掉了。
    private func markWindowsClosedOutsideRightScreen(among managedWindows: [ManagedWindow]) {
        guard
            let onScreenWindowIDs = windowController.onScreenWindowIDs(),
            managedWindows.contains(where: { onScreenWindowIDs.contains($0.windowID) })
        else {
            return
        }

        for window in managedWindows
        where windowController.isClosed(window, onScreenWindowIDs: onScreenWindowIDs) {
            destroyedWindowIDs.insert(window.windowID)
        }
    }

    private func removeClosedWindows(from session: LayoutSession) {
        markWindowsClosedOutsideRightScreen(among: session.panes.flatMap(\.windows))

        for paneIndex in session.panes.indices {
            var pane = session.panes[paneIndex]
            let selectedID = pane.windows.indices.contains(pane.selectedIndex)
                ? pane.windows[pane.selectedIndex].windowID
                : nil
            let liveWindows = pane.windows.filter { window in
                windowController.isAlive(window)
                    && !destroyedWindowIDs.contains(window.windowID)
            }
            guard liveWindows.count != pane.windows.count else { continue }

            let closedIDs = Set(pane.windows.map(\.windowID)).subtracting(liveWindows.map(\.windowID))
            session.autoJoinedWindowIDs.subtract(closedIDs)
            closingWindowIDs.subtract(closedIDs)
            // 关掉的窗口 ID 会被系统回收再利用，移出窗格后必须立刻忘记，
            // 否则同一个 ID 的新窗口会被当成已关闭的窗口，再也接管不了。
            destroyedWindowIDs.subtract(closedIDs)
            for windowID in closedIDs {
                cancelFrameEnforcement(for: windowID)
                session.originalFrames.removeValue(forKey: windowID)
            }
            pane.windows = liveWindows
            pane.activationHistory.removeAll { id in
                !liveWindows.contains(where: { $0.windowID == id })
            }
            var windowToRaise: ManagedWindow?
            if let selectedID, let retainedIndex = liveWindows.firstIndex(where: { $0.windowID == selectedID }) {
                pane.selectedIndex = retainedIndex
            } else {
                pane.selectedIndex = PaneTabHistory.selectedIndex(
                    remainingIDs: liveWindows.map(\.windowID),
                    history: pane.activationHistory,
                    removedIndex: pane.selectedIndex
                )
                windowToRaise = liveWindows.indices.contains(pane.selectedIndex)
                    ? liveWindows[pane.selectedIndex]
                    : nil
            }
            // 先把清理结果写回窗格，再去前置接任的窗口。
            // 顺序反过来的话，重排读到的仍是旧窗格：刚关掉的窗口还挂在「当前可见」名单里，
            // 会被当成需要盖回去的窗口再 raise 一次，于是 Shadowrocket 这类 App 被重新激活，
            // 一两秒后自己把窗口开了回来。
            session.panes[paneIndex] = pane
            if let windowToRaise {
                windowController.setAppKitFrame(pane.geometry.windowFrame, for: windowToRaise)
                raisePreservingOtherPanes(windowToRaise)
            }
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
        // 点到一个其实已经关掉的 Tab（Mac Catalyst App 关窗后 AX 元素还在）：
        // 绝不能去前置它，那等于替用户点了一次 Dock 图标，窗口会被重新开出来。
        // 交给统一的巡检判定：确认关掉就把 Tab 清掉，判不准就只留着，什么都不做。
        guard windowController.canActivate(selectedWindow) else {
            removeClosedWindows(from: session)
            return
        }
        windowController.setAppKitFrame(pane.geometry.windowFrame, for: selectedWindow)
        guard windowController.raise(selectedWindow) else {
            createOrUpdateTabBar(forPane: paneIndex, in: session)
            return
        }
        preserveVisibleWindowStack(keepingFront: selectedWindow)
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
                if self.windowController.isClosed(window) {
                    self.destroyedWindowIDs.insert(window.windowID)
                } else {
                    self.closingWindowIDs.remove(window.windowID)
                }
                if let session = self.session {
                    self.removeClosedWindows(from: session)
                }
                self.closeTasks[window.windowID] = nil
            }
        case .windowUnavailable:
            destroyedWindowIDs.insert(window.windowID)
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
        let geometries = LayoutEngine.geometries(
            for: .split2,
            in: resolvedScreen(for: session).visibleFrame
        )

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
            raisePreservingOtherPanes(focused)
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

        windowController.setAppKitFrame(targetPane.geometry.windowFrame, for: window)
        windowController.raise(window)
        scheduleFrameEnforcement(for: window.windowID)

        if !sourcePane.windows.isEmpty {
            let replacement = sourcePane.windows[sourcePane.selectedIndex]
            windowController.setAppKitFrame(sourcePane.geometry.windowFrame, for: replacement)
            windowController.raise(replacement)
            if restoreSourceFocus {
                session.lastFocusedPaneIndex = sourcePaneIndex
                preserveVisibleWindowStack(keepingFront: replacement)
                createOrUpdateTabBar(forPane: sourcePaneIndex, in: session)
                createOrUpdateTabBar(forPane: targetPaneIndex, in: session)
                return
            }
        }

        windowController.raise(window)
        session.lastFocusedPaneIndex = targetPaneIndex
        preserveVisibleWindowStack(keepingFront: window)
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
            let expectedAXFrame = ScreenIdentity.convertFrame(
                session.panes[membership.paneIndex].geometry.windowFrame
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
                    for: candidate
                )
                raisePreservingOtherPanes(candidate)
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
            // 等窗口稳定的这段时间里，用户可能已经把它关掉了。
            guard self.windowController.canActivate(window) else { return }

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
                windowController.setAppKitFrame(expected, for: window)
                return windowController.frameMatches(
                    window,
                    accessibilityFrame: ScreenIdentity.convertFrame(expected)
                )
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
            windowController.setAppKitFrame(leaf.frame, for: leaf.value)
            return windowController.frameMatches(
                leaf.value,
                accessibilityFrame: ScreenIdentity.convertFrame(leaf.frame)
            )
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

    @objc private func screenParametersDidChange(_ notification: Notification) {
        scheduleScreenRelayout()
    }

    private func scheduleScreenRelayout() {
        guard hasActiveLayout else { return }
        screenRelayoutTask?.cancel()
        screenRelayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in Self.screenRelayoutDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, self.hasActiveLayout else { return }
                self.relayoutForCurrentScreens()
            }
        }
    }

    private func relayoutForCurrentScreens() {
        if let session {
            relayoutTabSession(session)
        } else if let bentoSession {
            relayoutBentoSession(bentoSession)
        }
    }

    private func relayoutTabSession(_ session: LayoutSession) {
        guard !dropTracker.isTrackingMouseDrag else { return }

        let windows = session.panes.flatMap(\.windows)
        let visibleFrame = resolvedScreen(for: session, windows: windows).visibleFrame
        guard visibleFrame.width > 1, visibleFrame.height > 1 else { return }

        let geometries = LayoutEngine.geometries(for: session.kind, in: visibleFrame)
        guard geometries.count == session.panes.count else { return }

        for paneIndex in session.panes.indices {
            session.panes[paneIndex].geometry = geometries[paneIndex]
            let pane = session.panes[paneIndex]
            for window in pane.windows {
                windowController.setAppKitFrame(pane.geometry.windowFrame, for: window)
            }
            createOrUpdateTabBar(forPane: paneIndex, in: session)
        }
        dropTracker.updatePaneFrames(session.panes.map(\.geometry.paneFrame))
        for window in windows {
            scheduleFrameEnforcement(for: window.windowID)
        }
    }

    private func relayoutBentoSession(_ session: BentoSession) {
        guard !session.isDraggingDivider else { return }

        let windows = BentoEngine.leafValues(session.tree)
        _ = resolvedScreen(for: session, windows: windows)
        guard session.rootFrame.width > 1, session.rootFrame.height > 1 else { return }

        applyBentoFrames(session)
        session.dividerController?.update(dividers: session.dividerLayouts())
        for window in windows {
            scheduleFrameEnforcement(for: window.windowID)
        }
    }

    @discardableResult
    private func resolvedScreen(
        for session: LayoutSession,
        windows: [ManagedWindow]? = nil
    ) -> NSScreen {
        let liveWindows = windows ?? session.panes.flatMap(\.windows)
        let screen = resolveLayoutScreen(
            preferredDisplayID: session.displayID,
            windows: liveWindows
        ) ?? session.screen
        session.screen = screen
        session.displayID = ScreenIdentity.displayID(of: screen)
        return screen
    }

    @discardableResult
    private func resolvedScreen(
        for session: BentoSession,
        windows: [ManagedWindow]? = nil
    ) -> NSScreen {
        let liveWindows = windows ?? BentoEngine.leafValues(session.tree)
        let screen = resolveLayoutScreen(
            preferredDisplayID: session.displayID,
            windows: liveWindows
        ) ?? session.screen
        session.screen = screen
        session.displayID = ScreenIdentity.displayID(of: screen)
        return screen
    }

    private func resolveLayoutScreen(
        preferredDisplayID: CGDirectDisplayID,
        windows: [ManagedWindow]
    ) -> NSScreen? {
        if let screen = ScreenIdentity.screen(forDisplayID: preferredDisplayID) {
            return screen
        }

        let windowFrames = windows.compactMap { window -> CGRect? in
            guard let axFrame = AXHelpers.frame(of: window.element) else { return nil }
            return ScreenIdentity.convertFrame(axFrame)
        }
        let screens = NSScreen.screens
        if let index = ScreenIdentity.preferredScreenIndex(
            screenFrames: screens.map(\.frame),
            windowFrames: windowFrames
        ) {
            return screens[index]
        }
        return NSScreen.main ?? NSScreen.screens.first
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
